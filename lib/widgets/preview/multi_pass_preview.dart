import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../render/homography.dart';
import '../../render/mask_cache.dart';
import '../../utils/adjustment_throttler.dart';
import '../../state/providers.dart';

/// 离屏多 pass 预览
class MultiPassPreview extends ConsumerStatefulWidget {
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;
  final ui.FragmentProgram? sharpenProgram;
  final ui.FragmentProgram? denoiseProgram;
  final ui.FragmentProgram? perspectiveProgram;
  final ui.FragmentProgram? lensCorrectProgram;
  final int idleMaxEdge;
  final int draggingMaxEdge;

  const MultiPassPreview({
    super.key,
    required this.developProgram,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    this.sharpenProgram,
    this.denoiseProgram,
    this.perspectiveProgram,
    this.lensCorrectProgram,
    this.idleMaxEdge = 2400,
    this.draggingMaxEdge = 800,
  });

  @override
  ConsumerState<MultiPassPreview> createState() => _MultiPassPreviewState();
}

class _MultiPassPreviewState extends ConsumerState<MultiPassPreview> {
  ui.Image? _rendered;
  int _generation = 0;

  bool _isRendering = false;
  bool _pendingRender = false;

  late final _throttler = AdjustmentThrottler(ref)
    ..listen(onDragEnd: _scheduleHighQualityRerender);

  final _developCache = DevelopPassCache();
  final _brushCache = BrushMaskCache();
  final _perspectiveCache = PerspectiveMatrixCache();

  @override
  void initState() {
    super.initState();
    _scheduleRender();
  }

  @override
  void didUpdateWidget(MultiPassPreview old) {
    super.didUpdateWidget(old);
    if (old.sourceImage != widget.sourceImage) {
      _perspectiveCache.invalidate();
    }
    if (old.sourceImage != widget.sourceImage ||
        old.params != widget.params ||
        old.lutTexture != widget.lutTexture ||
        old.lutSize != widget.lutSize ||
        old.lutTextureB != widget.lutTextureB ||
        old.lutSizeB != widget.lutSizeB ||
        old.curveTexture != widget.curveTexture ||
        old.sharpenProgram != widget.sharpenProgram ||
        old.denoiseProgram != widget.denoiseProgram ||
        old.perspectiveProgram != widget.perspectiveProgram ||
        old.lensCorrectProgram != widget.lensCorrectProgram ||
        old.idleMaxEdge != widget.idleMaxEdge ||
        old.draggingMaxEdge != widget.draggingMaxEdge) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _throttler.dispose();
    _rendered?.dispose();
    _developCache.dispose();
    _brushCache.dispose();
    super.dispose();
  }

  void _scheduleRender() {
    _throttler.throttle(_runRender);
  }

  void _scheduleHighQualityRerender() {
    _throttler.throttle(
      _runRender,
      dragDelay: const Duration(milliseconds: 80),
    );
  }

  Future<void> _runRender() async {
    if (_isRendering) {
      _pendingRender = true;
      return;
    }
    _isRendering = true;
    _pendingRender = false;

    try {
      final gen = ++_generation;
      final src = widget.sourceImage;

      final isDragging = ref.read(isUserDraggingSliderProvider);
      final maxEdge = isDragging ? widget.draggingMaxEdge : widget.idleMaxEdge;

      final longest = math.max(src.width, src.height);
      final scale = longest > maxEdge ? maxEdge / longest : 1.0;
      final tw = (src.width * scale).round();
      final th = (src.height * scale).round();

      final result = await FullPipelineRenderer.render(
        developProgram: widget.developProgram,
        maskProgram: widget.maskProgram,
        sourceImage: src,
        params: widget.params,
        lutTexture: widget.lutTexture,
        lutSize: widget.lutSize,
        lutTextureB: widget.lutTextureB,
        lutSizeB: widget.lutSizeB,
        curveTexture: widget.curveTexture,
        sharpenProgram: widget.sharpenProgram,
        denoiseProgram: widget.denoiseProgram,
        perspectiveProgram: widget.perspectiveProgram,
        lensCorrectProgram: widget.lensCorrectProgram,
        perspectiveCache: _perspectiveCache,
        targetWidth: tw,
        targetHeight: th,
        developCache: _developCache,
        brushCache: _brushCache,
        allowStaleAutoMask: isDragging,
      );

      if (gen != _generation || !mounted) {
        result.dispose();
        return;
      }
      final old = _rendered;
      setState(() => _rendered = result);
      old?.dispose();
    } finally {
      _isRendering = false;
      if (_pendingRender) {
        _pendingRender = false;
        _scheduleRender();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rendered == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return SizedBox.expand(
      child: RawImage(image: _rendered, fit: BoxFit.fill),
    );
  }
}
