import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/lut_texture_cache.dart';
import '../../render/render_engine.dart';
import '../../services/lut/lut_library.dart';
import '../providers.dart';

/// LUT / 预设缩略图的统一状态
@immutable
class ThumbnailState {
  final Map<String, ui.Image> thumbs;
  final Set<String> rendering;
  const ThumbnailState({this.thumbs = const {}, this.rendering = const {}});

  ThumbnailState copyWith({
    Map<String, ui.Image>? thumbs,
    Set<String>? rendering,
  }) => ThumbnailState(
    thumbs: thumbs ?? this.thumbs,
    rendering: rendering ?? this.rendering,
  );
}

/// 统一缩略图渲染服务：LUT + 预设
///
/// key 命名空间：`lut:name` / `preset:id`
class ThumbnailCache extends Notifier<ThumbnailState> {
  static const _lutW = 60, _lutH = 40;
  static const _presetW = 80, _presetH = 56;

  bool _disposed = false;
  int? _lastSourceKey;
  int _gen = 0;

  // LUT 队列
  final _lutQueue = <_LutTask>[];
  bool _lutRunning = false;

  // 预设批量定时器
  Timer? _presetTimer;
  final _pendingPresets = <String, AdjustmentParams>{};

  @override
  ThumbnailState build() {
    ref.listen(imageNotifierProvider, (_, _) => _onSourceChanged());
    // ref.listen(currentParamsNotifierProvider, (_, _) => _onSourceChanged());
    ref.onDispose(() {
      _disposed = true;
      _presetTimer?.cancel();
      for (final img in state.thumbs.values) {
        try {
          img.dispose();
        } catch (_) {}
      }
    });
    return const ThumbnailState();
  }

  // ── 公开 API ──

  /// LUT 缩略图（60×40，含 LUT 纹理，串行队列）
  void requestLut(LutEntry entry) {
    final key = 'lut:${entry.name}';
    if (_disposed ||
        state.thumbs.containsKey(key) ||
        state.rendering.contains(key)) {
      return;
    }
    final image = ref.read(imageNotifierProvider).value;
    final program = ref.read(shaderProgramProvider).value;
    if (image == null || program == null) return;

    state = state.copyWith(rendering: {...state.rendering, key});
    _lutQueue.add(
      _LutTask(
        key: key,
        entry: entry,
        source: image.uiImage,
        params: ref.read(currentParamsNotifierProvider),
        program: program,
        sourceKey: _sourceKey(image.uiImage),
      ),
    );
    if (!_lutRunning) _processLutQueue();
  }

  /// 预设缩略图（80×56，仅 develop pass，首帧防抖批量触发）
  void requestPreset(String id, AdjustmentParams params) {
    final key = 'preset:$id';
    if (_disposed ||
        state.thumbs.containsKey(key) ||
        state.rendering.contains(key)) {
      return;
    }
    _pendingPresets[key] = params;
    _presetTimer?.cancel();
    // 100ms 防抖：同帧内多次 request 合并为一批
    _presetTimer = Timer(const Duration(milliseconds: 100), () {
      _presetTimer = null;
      _renderPresetBatch(Map.of(_pendingPresets));
      _pendingPresets.clear();
    });
  }

  // ── LUT 渲染 ──

  void _processLutQueue() {
    if (_lutRunning || _lutQueue.isEmpty) return;
    _lutRunning = true;
    final gen = _gen;
    Future.doWhile(() async {
      if (_disposed || gen != _gen || _lutQueue.isEmpty) return false;
      final task = _lutQueue.removeAt(0);
      if (task.sourceKey != _lastSourceKey) {
        state = state.copyWith(
          rendering: {...state.rendering}..remove(task.key),
        );
        return _lutQueue.isNotEmpty;
      }
      await _renderLut(task, gen);
      return _lutQueue.isNotEmpty;
    }).whenComplete(() => _lutRunning = false);
  }

  Future<void> _renderLut(_LutTask task, int gen) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (_disposed || task.sourceKey != _lastSourceKey || gen != _gen) {
      state = state.copyWith(rendering: {...state.rendering}..remove(task.key));
      return;
    }
    final safe = task.source.clone();
    try {
      final lutTex = await LutTextureCache.instance.load(task.entry.name);
      if (_disposed ||
          task.sourceKey != _lastSourceKey ||
          gen != _gen ||
          lutTex == null) {
        state = state.copyWith(
          rendering: {...state.rendering}..remove(task.key),
        );
        return;
      }
      final result = await _render(
        task.program,
        safe,
        task.params,
        _lutW,
        _lutH,
        lutA: lutTex.texture,
        lutSizeA: lutTex.size,
        lutNameA: task.entry.name,
      );
      if (_disposed || task.sourceKey != _lastSourceKey || gen != _gen) {
        result?.dispose();
        return;
      }
      if (result != null) _commit(task.key, result);
    } catch (_) {
    } finally {
      state = state.copyWith(rendering: {...state.rendering}..remove(task.key));
      safe.dispose();
    }
  }

  // ── 预设渲染 ──

  void _renderPresetBatch(Map<String, AdjustmentParams> batch) {
    final image = ref.read(imageNotifierProvider).value;
    final program = ref.read(shaderProgramProvider).value;
    if (_disposed || image == null || program == null) return;
    final gen = ++_gen;
    final sourceKey = _sourceKey(image.uiImage);
    final keys = batch.keys.toList();
    state = state.copyWith(rendering: {...state.rendering, ...keys});

    for (final entry in batch.entries) {
      _renderPreset(
        entry.key,
        entry.value,
        image.uiImage,
        program,
        gen,
        sourceKey,
      );
    }
  }

  Future<void> _renderPreset(
    String key,
    AdjustmentParams params,
    ui.Image source,
    ui.FragmentProgram program,
    int gen,
    int sourceKey,
  ) async {
    await Future.delayed(const Duration(milliseconds: 16));
    if (_disposed || gen != _gen || sourceKey != _lastSourceKey) {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      return;
    }
    final safe = source.clone();
    try {
      final result = await _render(program, safe, params, _presetW, _presetH);
      if (_disposed || gen != _gen || sourceKey != _lastSourceKey) {
        result?.dispose();
        return;
      }
      if (result != null) _commit(key, result);
    } catch (_) {
    } finally {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      safe.dispose();
    }
  }

  // ── 共享渲染 ──

  Future<ui.Image?> _render(
    ui.FragmentProgram program,
    ui.Image source,
    AdjustmentParams params,
    int w,
    int h, {
    ui.Image? lutA,
    int lutSizeA = 0,
    String lutNameA = '',
  }) async {
    final clean = params.copyWith(
      lutNameA: lutNameA,
      lutIntensity: lutA != null ? 1.0 : 0.0,
      lutNameB: '',
      lutIntensityB: 0.0,
      locals: const [],
      sharpenAmount: 0,
      denoiseLuma: 0,
      denoiseColor: 0,
    );
    return RenderEngine.renderToImage(
      program: program,
      sourceImage: source,
      params: clean,
      lutTexture: lutA,
      lutSize: lutSizeA,
      targetWidth: w,
      targetHeight: h,
    );
  }

  void _commit(String key, ui.Image img) {
    final old = state.thumbs[key];
    state = ThumbnailState(
      thumbs: {...state.thumbs, key: img},
      rendering: {...state.rendering}..remove(key),
    );
    old?.dispose();
  }

  // ── 源图变更 ──

  int _sourceKey(ui.Image src) => identityHashCode(src);

  void _onSourceChanged() {
    final image = ref.read(imageNotifierProvider).value;
    if (image == null) return;
    final key = _sourceKey(image.uiImage);
    if (key == _lastSourceKey) return;
    _lastSourceKey = key;
    _gen++;
    _lutQueue.clear();
    _lutRunning = false;
    _presetTimer?.cancel();
    _pendingPresets.clear();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final old = Map<String, ui.Image>.from(state.thumbs);
      state = const ThumbnailState();
      Future.delayed(const Duration(milliseconds: 300), () {
        for (final img in old.values) {
          try {
            img.dispose();
          } catch (_) {}
        }
      });
    });
  }
}

final thumbnailCacheProvider = NotifierProvider<ThumbnailCache, ThumbnailState>(
  ThumbnailCache.new,
);

class _LutTask {
  final String key;
  final LutEntry entry;
  final ui.Image source;
  final AdjustmentParams params;
  final ui.FragmentProgram program;
  final int sourceKey;
  const _LutTask({
    required this.key,
    required this.entry,
    required this.source,
    required this.params,
    required this.program,
    required this.sourceKey,
  });
}
