import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../render/crop_transform.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../render/hi_res_pyramid.dart';
import '../../utils/debouncer.dart';
import '../providers.dart';

@immutable
class HiResRenderState {
  /// 各层级渲染出的裁剪后输出（key = 层级，0 = 全尺寸）
  final Map<int, ui.Image> levels;
  final bool rendering;
  const HiResRenderState({this.levels = const {}, this.rendering = false});
}

/// 超清按需分辨率渲染：按 zoom 所需层级跑管线（target = src ~/ 2^k），缓存各层级
///
/// 不写 developOutputProvider / composeGuideProvider / renderedPreviewGenerationProvider
class HiResRenderNotifier extends Notifier<HiResRenderState> {
  int _gen = 0;
  bool _rendering = false;
  bool _pending = false;
  bool _disposed = false;
  int _renderedParamsHash = 0;
  final _settle = Debouncer();

  @override
  HiResRenderState build() {
    ref.listen(hiResActiveProvider, (prev, next) {
      if (next && prev != true) _triggerRender();
      if (!next && prev == true) _evict(immediate: false);
    });
    ref.listen(hiResSourceProvider, (_, _) => _triggerRender());
    ref.listen(zoomScaleProvider, (prev, next) {
      if (prev != next && ref.read(hiResActiveProvider)) _triggerRender();
    });
    ref.listen(isUserDraggingSliderProvider, (prev, next) {
      if (prev == true && next == false) _triggerRender();
    });
    ref.listen(debouncedParamsProvider, (prev, next) {
      if (!ref.read(hiResActiveProvider)) return;
      if (next == prev) return;
      // 参数（含 crop）变了：清空所有已渲染层级防陈旧错位，再 settle 后重渲
      if (next.hashCode != _renderedParamsHash && state.levels.isNotEmpty) {
        _evict(immediate: true);
      }
      _triggerRender();
    });
    ref.onDispose(() {
      _disposed = true;
      _settle.dispose();
      _disposeLevels(state.levels);
    });
    return const HiResRenderState();
  }

  /// 延迟触发渲染：交互（缩放/平移/拖滑块）停止 200ms 后才真正渲染，
  /// 避免全尺寸 GPU 管线渲染与交互帧竞争导致掉帧。
  void _triggerRender() {
    _settle.run(const Duration(milliseconds: 200), _schedule);
  }

  Future<void> _schedule() async {
    if (_rendering) {
      _pending = true;
      return;
    }
    if (!ref.read(hiResActiveProvider)) return;
    if (ref.read(isUserDraggingSliderProvider)) return;
    final src = ref.read(hiResSourceProvider);
    if (src == null) return;
    final displaySize = ref.read(hiResDisplaySizeProvider);
    if (displaySize == null) return;

    final params = ref.read(debouncedParamsProvider);
    final zoom = ref.read(zoomScaleProvider);
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final fullOutSize = cropOutputSize(params.crop, src.width, src.height);
    final targetLevel = selectPyramidLevel(
      zoom: zoom,
      devicePixelRatio: dpr,
      displaySize: displaySize,
      fullOutSize: fullOutSize,
    );

    // 该层级已渲染（且参数未变）→ 复用
    if (state.levels.containsKey(targetLevel)) return;

    _rendering = true;
    _pending = false;
    final gen = ++_gen;
    try {
      final scale = 1 << targetLevel;
      final result = await FullPipelineRenderer.renderFromRef(
        ref,
        sourceImage: src,
        params: params,
        targetWidth: src.width ~/ scale,
        targetHeight: src.height ~/ scale,
        includeBrushLayers: true,
      );
      if (_disposed) return;
      if (gen != _gen) {
        result?.finalImage.dispose();
        result?.developOutput?.dispose();
        return;
      }
      if (result == null) return; // shader 未就绪，下次触发再试

      final levels = Map<int, ui.Image>.from(state.levels);
      final old = levels[targetLevel];
      levels[targetLevel] = result.finalImage;
      if (old != null) _disposeLater(old);
      state = HiResRenderState(levels: levels, rendering: false);
      _renderedParamsHash = params.hashCode;
    } catch (e) {
      debugPrint('[HiResRender] failed: $e');
    } finally {
      _rendering = false;
      if (_pending && !_disposed) {
        _pending = false;
        _schedule();
      }
    }
  }

  void _evict({required bool immediate}) {
    if (immediate) {
      _disposeLevels(state.levels);
      state = const HiResRenderState();
      return;
    }
    final levels = state.levels;
    if (levels.isEmpty) return;
    // 缩回低阈值后延迟逐出（2s 宽限，避免来回缩放反复重渲）
    Future.delayed(const Duration(seconds: 2), () {
      if (_disposed) return;
      if (!ref.read(hiResActiveProvider) && identical(state.levels, levels)) {
        _disposeLevels(state.levels);
        state = const HiResRenderState();
      }
    });
  }

  void _disposeLevels(Map<int, ui.Image> levels) {
    for (final img in levels.values) {
      _disposeLater(img);
    }
  }

  void _disposeLater(ui.Image img) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      try {
        img.dispose();
      } catch (_) {}
    });
  }
}

final hiResCroppedImageProvider =
    NotifierProvider<HiResRenderNotifier, HiResRenderState>(
      HiResRenderNotifier.new,
    );
