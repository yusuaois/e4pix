import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../render/lut_texture_cache.dart';
import '../render/render_engine.dart';
import '../services/lut_library.dart';
import 'providers.dart';

/// LUT 缩略图渲染服务的状态快照（不可变）
@immutable
class LutThumbnailState {
  final Map<String, ui.Image> thumbs;
  final Set<String> rendering;
  const LutThumbnailState({this.thumbs = const {}, this.rendering = const {}});

  LutThumbnailState copyWith({
    Map<String, ui.Image>? thumbs,
    Set<String>? rendering,
  }) => LutThumbnailState(
    thumbs: thumbs ?? this.thumbs,
    rendering: rendering ?? this.rendering,
  );
}

/// LUT 缩略图渲染队列引擎。
///
/// 按需触发（菜单项可见时才排队），串行渲染，代数追踪防止过时结果覆盖
/// 缩略图尺寸 60×40，仅跑 develop + LUT pass，跳过 local/sharpen/denoise
class LutThumbnailNotifier extends Notifier<LutThumbnailState> {
  static const _thumbW = 60;
  static const _thumbH = 40;

  bool _disposed = false;
  int? _lastSourceKey;
  final _renderQueue = <_RenderTask>[];
  bool _queueRunning = false;
  int _queueGeneration = 0;
  final _pendingThumbs = <String, ui.Image>{};
  bool _batchScheduled = false;

  @override
  LutThumbnailState build() {
    // 监听源图/参数变更，自动清空过时缩略图
    ref.listen(imageNotifierProvider, (prev, next) => _onSourceChanged());
    ref.listen(currentParamsNotifierProvider, (prev, next) => _onSourceChanged());

    ref.onDispose(() {
      _disposed = true;
      _renderQueue.clear();
      for (final img in _pendingThumbs.values) {
        try { img.dispose(); } catch (_) {}
      }
      _pendingThumbs.clear();
      for (final img in state.thumbs.values) {
        try { img.dispose(); } catch (_) {}
      }
    });
    return const LutThumbnailState();
  }

  void _onSourceChanged() {
    final image = ref.read(imageNotifierProvider).value;
    final params = ref.read(currentParamsNotifierProvider);
    if (image == null) return;
    final key = _computeKey(image.uiImage, params);
    if (key == _lastSourceKey) return;
    _lastSourceKey = key;
    // defer 到下一帧避免 "modify provider during build" 错误
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _invalidateAll();
    });
  }

  // ── 公开 API ──

  /// 触发指定 LUT 条目的缩略图渲染（入口已去重）。
  void requestRender(LutEntry entry) {
    final image = ref.read(imageNotifierProvider).value;
    final params = ref.read(currentParamsNotifierProvider);
    final developProgram = ref.read(shaderProgramProvider).value;
    if (_disposed || image == null || developProgram == null) return;
    if (state.thumbs.containsKey(entry.name) ||
        state.rendering.contains(entry.name)) {
      return;
    }

    state = state.copyWith(rendering: {...state.rendering, entry.name});
    _renderQueue.add(_RenderTask(
      entry: entry,
      sourceImage: image.uiImage,
      params: params,
      developProgram: developProgram,
      sourceKey: _computeKey(image.uiImage, params),
    ));

    if (!_queueRunning) _processQueue();
  }

  // ── 内部 ──

  /// LUT 参数不影响 key，所以切换 LUT 时不会清空其他 LUT 的缩略图
  int _computeKey(ui.Image src, AdjustmentParams params) {
    final base = params.copyWith(
      lutNameA: '',
      lutIntensity: 1.0,
      lutNameB: '',
      lutIntensityB: 1.0,
    );
    return Object.hash(identityHashCode(src), base.hashCode);
  }

  void _invalidateAll() {
    // 取消所有排队任务
    _renderQueue.clear();
    _pendingThumbs.clear();
    _batchScheduled = false;
    _queueGeneration++;

    final oldThumbs = Map<String, ui.Image>.from(state.thumbs);
    state = state.copyWith(thumbs: const {}, rendering: const {});
    if (oldThumbs.isEmpty) return;

    // 延迟释放：确保当前帧渲染引用已结束
    Future.delayed(const Duration(milliseconds: 600), () {
      for (final img in oldThumbs.values) {
        try { img.dispose(); } catch (_) {}
      }
    });
  }

  void _flushBatch() {
    if (_batchScheduled || _disposed || _pendingThumbs.isEmpty) return;
    _batchScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _batchScheduled = false;
      if (_disposed || _pendingThumbs.isEmpty) return;
      final batch = Map<String, ui.Image>.from(_pendingThumbs);
      _pendingThumbs.clear();
      state = state.copyWith(
        thumbs: {...state.thumbs, ...batch},
        rendering: {...state.rendering}, // keep current rendering state
      );
    });
  }

  Future<void> _processQueue() async {
    if (_queueRunning || _renderQueue.isEmpty) return;
    _queueRunning = true;
    final gen = _queueGeneration;

    while (_renderQueue.isNotEmpty) {
      if (_disposed || gen != _queueGeneration) {
        _renderQueue.clear();
        break;
      }

      final task = _renderQueue.removeAt(0);
      if (task.sourceKey != _lastSourceKey || gen != _queueGeneration) {
        state = state.copyWith(
          rendering: {...state.rendering}..remove(task.entry.name),
        );
        continue;
      }

      await _renderOne(task, gen);
    }

    _queueRunning = false;
  }

  Future<void> _renderOne(_RenderTask task, int gen) async {
    // 让出事件循环，给切图操作留出时间
    await Future.delayed(const Duration(milliseconds: 50));
    if (_disposed || task.sourceKey != _lastSourceKey || gen != _queueGeneration) {
      state = state.copyWith(
        rendering: {...state.rendering}..remove(task.entry.name),
      );
      return;
    }

    final safeSource = task.sourceImage.clone();
    try {
      final lutTex = await LutTextureCache.instance.load(task.entry.name);
      if (_disposed ||
          task.sourceKey != _lastSourceKey ||
          gen != _queueGeneration ||
          lutTex == null) {
        state = state.copyWith(
          rendering: {...state.rendering}..remove(task.entry.name),
        );
        return;
      }

      final cleanParams = task.params.copyWith(
        lutNameA: task.entry.name,
        lutIntensity: 1.0,
        lutNameB: '',
        lutIntensityB: 1.0,
        locals: const [],
        sharpenAmount: 0,
        denoiseLuma: 0,
        denoiseColor: 0,
      );

      final result = await RenderEngine.renderToImage(
        program: task.developProgram,
        sourceImage: safeSource,
        params: cleanParams,
        lutTexture: lutTex.texture,
        lutSize: lutTex.size,
        targetWidth: _thumbW,
        targetHeight: _thumbH,
      );

      if (_disposed || task.sourceKey != _lastSourceKey || gen != _queueGeneration) {
        result.dispose();
        return;
      }

      final old = state.thumbs[task.entry.name];
      _pendingThumbs[task.entry.name] = result;
      _flushBatch();
      old?.dispose();
    } catch (e, stack) {
      debugPrint('[LUT] Error rendering thumbnail for ${task.entry.name}: $e');
      debugPrint('[LUT] Stack trace: $stack');
    } finally {
      state = state.copyWith(
        rendering: {...state.rendering}..remove(task.entry.name),
      );
      safeSource.dispose();
    }
  }
}

/// 由 providers.dart 统一导出
final lutThumbnailProvider =
    NotifierProvider<LutThumbnailNotifier, LutThumbnailState>(
      LutThumbnailNotifier.new,
    );

// ── 内部类型 ──

class _RenderTask {
  final LutEntry entry;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.FragmentProgram developProgram;
  final int sourceKey;
  const _RenderTask({
    required this.entry,
    required this.sourceImage,
    required this.params,
    required this.developProgram,
    required this.sourceKey,
  });
}
