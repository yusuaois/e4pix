import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brushes/brush_manifest.dart';
import '../core/models/adjustment_params.dart';
import 'brush_layer_provider.dart';
import 'brush_layer_registry.dart';
import 'full_pipeline_renderer.dart';
import 'lut_texture_cache.dart';
import 'render_engine.dart';
import '../services/lut/lut_library.dart';
import '../state/image/image_state.dart';
import '../state/params/params_state.dart';
import '../state/render/render_state.dart';
import '../utils/debouncer.dart';

/// 缩略图渲染的统一状态
@immutable
class ThumbnailRenderState {
  final Map<String, ui.Image> thumbs;
  final Set<String> rendering;
  const ThumbnailRenderState({
    this.thumbs = const {},
    this.rendering = const {},
  });

  ThumbnailRenderState copyWith({
    Map<String, ui.Image>? thumbs,
    Set<String>? rendering,
  }) => ThumbnailRenderState(
    thumbs: thumbs ?? this.thumbs,
    rendering: rendering ?? this.rendering,
  );
}

/// 通用缩略图渲染服务
///
/// key 命名空间：`lut:name` / `preset:id` / `history:id`
class ThumbnailRenderer extends Notifier<ThumbnailRenderState> {
  bool _disposed = false;
  int? _lastSourceKey;
  int _gen = 0;

  // LUT 队列
  final _lutQueue = <_LutTask>[];
  bool _lutRunning = false;

  // 依赖未就绪时的暂存请求
  final _pendingLuts = <String, LutEntry>{};

  // 预设批量防抖
  final _presetDebouncer = Debouncer();
  final _pendingPresets = <String, _PresetRequest>{};

  // 全管线渲染 brush layer provider 惰性创建
  final _brushLayers = <String, BrushLayerProvider>{};

  @override
  ThumbnailRenderState build() {
    // ref.listen 不触发初始值：若 image 已就绪则手动初始化 _lastSourceKey，
    // 否则 _processLutQueue / _renderPreset 的 sourceKey 检查会丢弃所有渲染结果
    final initial = ref.read(imageNotifierProvider).value;
    if (initial != null && _lastSourceKey == null) {
      _lastSourceKey = _sourceKey(initial.uiImage);
    }

    ref.listen(imageNotifierProvider, (prev, next) {
      _onSourceChanged();
      if (next.hasValue && prev is AsyncLoading) _retryPending();
    });
    ref.listen(currentParamsNotifierProvider, (_, _) => _onSourceChanged());
    ref.listen(shaderProgramProvider, (prev, next) {
      if (next.hasValue && prev is AsyncLoading) _retryPending();
    });
    ref.onDispose(() {
      _disposed = true;
      _presetDebouncer.dispose();
      for (final img in state.thumbs.values) {
        try {
          img.dispose();
        } catch (_) {}
      }
      for (final p in _brushLayers.values) {
        p.dispose();
      }
    });
    return const ThumbnailRenderState();
  }

  // ── 公开 API ──

  /// 带 LUT 纹理的缩略图（默认 60×40，串行队列）
  void requestWithLut(LutEntry entry, {int w = 60, int h = 40}) {
    final key = 'lut:${entry.name}';
    if (_disposed ||
        state.thumbs.containsKey(key) ||
        state.rendering.contains(key)) {
      return;
    }
    final image = ref.read(imageNotifierProvider).value;
    final program = ref.read(shaderProgramProvider).value;
    if (image == null || program == null) {
      _pendingLuts[key] = entry;
      return;
    }

    state = state.copyWith(rendering: {...state.rendering, key});
    _lutQueue.add(
      _LutTask(
        key: key,
        entry: entry,
        source: image.uiImage,
        params: ref.read(currentParamsNotifierProvider),
        program: program,
        sourceKey: _sourceKey(image.uiImage),
        w: w,
        h: h,
      ),
    );
    if (!_lutRunning) _processLutQueue();
  }

  /// 基础 develop-pass 缩略图（默认 80×56，首帧防抖批量触发）
  void request(String id, AdjustmentParams params, {int w = 80, int h = 56}) {
    final key = 'preset:$id';
    if (_disposed ||
        state.thumbs.containsKey(key) ||
        state.rendering.contains(key)) {
      return;
    }
    _pendingPresets[key] = _PresetRequest(params: params, w: w, h: h);
    _presetDebouncer.run(const Duration(milliseconds: 100), () {
      _renderPresetBatch(Map.of(_pendingPresets));
    });
  }

  /// 全管线缩略图（通过 [FullPipelineRenderer] 渲染，含画笔/锐化/降噪等全部 pass）
  ///
  /// [namespace] = 键前缀（如 `history`），[id] = 唯一标识符，key 格式 `namespace:id`
  /// [w] / [h] = 输出像素尺寸
  void requestFull(
    String namespace,
    String id,
    AdjustmentParams params, {
    int w = 120,
    int h = 80,
  }) {
    final key = '$namespace:$id';
    if (_disposed ||
        state.thumbs.containsKey(key) ||
        state.rendering.contains(key)) {
      return;
    }
    final image = ref.read(imageNotifierProvider).value;
    if (image == null) {
      // 依赖未就绪：暂存以待 _retryPending 重播
      _pendingPresets[key] = _PresetRequest(params: params, w: w, h: h);
      return;
    }
    final gen = ++_gen;
    final sourceKey = _sourceKey(image.uiImage);
    state = state.copyWith(rendering: {...state.rendering, key});
    _renderFull(key, params, image.uiImage, gen, sourceKey, w, h);
  }

  // LUT 渲染

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
      final result = await _renderDevelop(
        task.program,
        safe,
        task.params,
        task.w,
        task.h,
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

  // 预设渲染

  void _renderPresetBatch(Map<String, _PresetRequest> batch) {
    final image = ref.read(imageNotifierProvider).value;
    final program = ref.read(shaderProgramProvider).value;
    if (_disposed || image == null || program == null) return;
    final gen = ++_gen;
    final sourceKey = _sourceKey(image.uiImage);
    final keys = batch.keys.toList();
    state = state.copyWith(rendering: {...state.rendering, ...keys});
    _pendingPresets.removeWhere((k, _) => keys.contains(k));

    for (final entry in batch.entries) {
      _renderPreset(
        entry.key,
        entry.value.params,
        image.uiImage,
        program,
        gen,
        sourceKey,
        entry.value.w,
        entry.value.h,
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
    int w,
    int h,
  ) async {
    await Future.delayed(const Duration(milliseconds: 16));
    if (_disposed || gen != _gen || sourceKey != _lastSourceKey) {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      return;
    }
    final safe = source.clone();
    try {
      final result = await _renderDevelop(program, safe, params, w, h);
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

  // 全管线渲染

  Future<void> _renderFull(
    String key,
    AdjustmentParams params,
    ui.Image source,
    int gen,
    int sourceKey,
    int w,
    int h,
  ) async {
    await Future.delayed(const Duration(milliseconds: 16));
    if (_disposed || gen != _gen || sourceKey != _lastSourceKey) {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      return;
    }

    // 读取全管线所需 shader（各 provider 共享 _allShadersProvider 的批量加载结果）
    final developProgram = ref.read(shaderProgramProvider).value;
    final maskProgram = ref.read(maskShaderProgramProvider).value;
    if (developProgram == null || maskProgram == null) {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      return;
    }
    final sharpenProgram = ref.read(sharpenShaderProgramProvider).value;
    final denoiseProgram = ref.read(denoiseShaderProgramProvider).value;
    final perspectiveProgram = ref.read(perspectiveShaderProgramProvider).value;
    final lensCorrectProgram = ref.read(lensCorrectShaderProgramProvider).value;

    // 构建 brush layer registry
    BrushLayerRegistry? brushReg;
    try {
      final brushPrograms = ref.read(brushShaderProgramsProvider).value ?? {};
      final providers = <BrushLayerProvider>[];
      for (final m in brushManifests) {
        final prog = brushPrograms[m.id];
        if (prog != null) {
          _brushLayers.putIfAbsent(m.id, () => m.layerFactory(prog));
          providers.add(_brushLayers[m.id]!);
        }
      }
      if (providers.isNotEmpty) {
        brushReg = BrushLayerRegistry(providers: providers);
      }
    } catch (_) {}

    // curve 纹理
    final curveTexture = ref.read(curveTextureProvider);

    // LUT 纹理
    ui.Image? lutA;
    int lutSizeA = 0;
    if (params.lutNameA.isNotEmpty) {
      final tex = await LutTextureCache.instance.load(params.lutNameA);
      lutA = tex?.texture;
      lutSizeA = tex?.size ?? 0;
    }
    ui.Image? lutB;
    int lutSizeB = 0;
    if (params.lutNameB.isNotEmpty) {
      final tex = await LutTextureCache.instance.load(params.lutNameB);
      lutB = tex?.texture;
      lutSizeB = tex?.size ?? 0;
    }

    if (_disposed || gen != _gen || sourceKey != _lastSourceKey) {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      return;
    }

    final safe = source.clone();
    try {
      final result = await FullPipelineRenderer.render(
        developProgram: developProgram,
        maskProgram: maskProgram,
        sharpenProgram: sharpenProgram,
        denoiseProgram: denoiseProgram,
        perspectiveProgram: perspectiveProgram,
        lensCorrectProgram: lensCorrectProgram,
        brushLayerRegistry: brushReg,
        sourceImage: safe,
        params: params,
        lutTexture: lutA,
        lutSize: lutSizeA,
        lutTextureB: lutB,
        lutSizeB: lutSizeB,
        curveTexture: curveTexture,
        targetWidth: w,
        targetHeight: h,
      );
      if (_disposed || gen != _gen || sourceKey != _lastSourceKey) {
        result.finalImage.dispose();
        result.developOutput?.dispose();
        return;
      }
      result.developOutput?.dispose();
      _commit(key, result.finalImage);
    } catch (_) {
    } finally {
      state = state.copyWith(rendering: {...state.rendering}..remove(key));
      safe.dispose();
    }
  }

  /// 移除指定前缀的所有缩略图
  void removeNamespace(String prefix) {
    final toRemove = state.thumbs.keys
        .where((k) => k.startsWith('$prefix:'))
        .toList();
    if (toRemove.isEmpty) return;
    final newThumbs = Map<String, ui.Image>.from(state.thumbs);
    for (final key in toRemove) {
      newThumbs.remove(key)?.dispose();
    }
    state = ThumbnailRenderState(
      thumbs: newThumbs,
      rendering: {...state.rendering}
        ..removeWhere((k) => k.startsWith('$prefix:')),
    );
  }

  // 基础 develop-pass 渲染（LUT/Preset 用）

  Future<ui.Image?> _renderDevelop(
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
    state = ThumbnailRenderState(
      thumbs: {...state.thumbs, key: img},
      rendering: {...state.rendering}..remove(key),
    );
    old?.dispose();
  }

  // ── 重试暂存请求 ──

  void _retryPending() {
    for (final entry in Map.of(_pendingLuts).entries) {
      _pendingLuts.remove(entry.key);
      requestWithLut(entry.value);
    }
    if (_pendingPresets.isNotEmpty) {
      _presetDebouncer.run(const Duration(milliseconds: 100), () {
        _renderPresetBatch(Map.of(_pendingPresets));
      });
    }
  }

  // ── 源图变更 ──

  int _sourceKey(ui.Image src) => identityHashCode(src);

  void _onSourceChanged() {
    final image = ref.read(imageNotifierProvider).value;
    if (image == null) return;
    final key = _sourceKey(image.uiImage);
    if (key == _lastSourceKey) return;
    // 首次初始化：仅记录 key，不清除暂存请求
    if (_lastSourceKey == null) {
      _lastSourceKey = key;
      return;
    }
    _lastSourceKey = key;
    _gen++;
    _lutQueue.clear();
    _lutRunning = false;
    _pendingLuts.clear();
    _presetDebouncer.cancel();
    _pendingPresets.clear();

    // 使 brush layer 缓存失效
    for (final p in _brushLayers.values) {
      p.invalidate();
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final old = Map<String, ui.Image>.from(state.thumbs);
      state = const ThumbnailRenderState();
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

final thumbnailRendererProvider =
    NotifierProvider<ThumbnailRenderer, ThumbnailRenderState>(
      ThumbnailRenderer.new,
    );

class _LutTask {
  final String key;
  final LutEntry entry;
  final ui.Image source;
  final AdjustmentParams params;
  final ui.FragmentProgram program;
  final int sourceKey;
  final int w;
  final int h;
  const _LutTask({
    required this.key,
    required this.entry,
    required this.source,
    required this.params,
    required this.program,
    required this.sourceKey,
    required this.w,
    required this.h,
  });
}

class _PresetRequest {
  final AdjustmentParams params;
  final int w;
  final int h;
  const _PresetRequest({
    required this.params,
    required this.w,
    required this.h,
  });
}
