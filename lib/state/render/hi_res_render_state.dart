import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../render/full_pipeline_renderer.dart';
import '../../utils/debouncer.dart';
import '../providers.dart';

@immutable
class HiResRenderState {
  final ui.Image? image; // 全尺寸裁剪后输出；null = 未就绪/已逐出
  final bool rendering;
  const HiResRenderState({this.image, this.rendering = false});
}

/// 超清渲染：zoom 超阈值且参数稳定后，后台把全尺寸源跑一遍完整管线，
/// 产出「全尺寸裁剪后输出图」供显示层按视口切瓦片。
///
/// 不写 developOutputProvider / composeGuideProvider / renderedPreviewGenerationProvider，
/// 避免污染画笔 overlay 与选区服务（这些副作用只属于低清 MultiPassPreview）。
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
      // 缩放过程中持续重置 settle，停止 200ms 后才渲染，避免和缩放帧抢 GPU
      if (prev != next && ref.read(hiResActiveProvider)) _triggerRender();
    });
    ref.listen(isUserDraggingSliderProvider, (prev, next) {
      if (prev == true && next == false) _triggerRender();
    });
    ref.listen(debouncedParamsProvider, (prev, next) {
      if (!ref.read(hiResActiveProvider)) return;
      if (next == prev) return;
      // 参数（含 crop）变了：先退旧图防陈旧错位，再 settle 后重渲
      if (next.hashCode != _renderedParamsHash && state.image != null) {
        _evict(immediate: true);
      }
      _triggerRender();
    });
    ref.onDispose(() {
      _disposed = true;
      _settle.dispose();
      _disposeImage();
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

    _rendering = true;
    _pending = false;
    final gen = ++_gen;
    try {
      final params = ref.read(debouncedParamsProvider);
      final result = await FullPipelineRenderer.renderFromRef(
        ref,
        sourceImage: src,
        params: params,
        targetWidth: src.width,
        targetHeight: src.height,
        includeBrushLayers: true,
      );
      if (_disposed) return;
      if (gen != _gen) {
        result?.finalImage.dispose();
        result?.developOutput?.dispose();
        return;
      }
      if (result == null) return; // shader 未就绪，下次触发再试
      _disposeImage();
      state = HiResRenderState(image: result.finalImage, rendering: false);
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
      _disposeImage();
      state = const HiResRenderState();
      return;
    }
    final img = state.image;
    if (img == null) return;
    // 缩回低阈值后延迟逐出（2s 宽限，避免来回缩放反复重渲）
    Future.delayed(const Duration(seconds: 2), () {
      if (_disposed) return;
      if (!ref.read(hiResActiveProvider) && identical(state.image, img)) {
        _disposeImage();
        state = const HiResRenderState();
      }
    });
  }

  void _disposeImage() {
    final img = state.image;
    if (img == null) return;
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
