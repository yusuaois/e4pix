import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../render/full_pipeline_renderer.dart';
import '../render/mask_cache.dart';
import '../state/interaction_state.dart';

/// 离屏多 pass 预览
class MultiPassPreview extends ConsumerStatefulWidget {
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
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
    this.idleMaxEdge = 2400,
    this.draggingMaxEdge = 800,
  });

  @override
  ConsumerState<MultiPassPreview> createState() => _MultiPassPreviewState();
}

class _MultiPassPreviewState extends ConsumerState<MultiPassPreview> {
  ui.Image? _rendered;
  int _generation = 0;

  Timer? _throttle;
  bool _isRendering = false;
  bool _pendingRender = false;

  ProviderSubscription<bool>? _dragSub;

  final _developCache = DevelopPassCache();
  final _brushCache = BrushMaskCache();

  @override
  void initState() {
    super.initState();
    _dragSub = ref.listenManual<bool>(isUserDraggingSliderProvider, (
      prev,
      next,
    ) {
      if (prev == true && next == false) {
        _scheduleHighQualityRerender();
      }
    });
    _scheduleRender();
  }

  @override
  void didUpdateWidget(MultiPassPreview old) {
    super.didUpdateWidget(old);
    if (old.sourceImage != widget.sourceImage ||
        old.params != widget.params ||
        old.lutTexture != widget.lutTexture ||
        old.lutSize != widget.lutSize) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _dragSub?.close();
    _rendered?.dispose();
    _developCache.dispose();
    _brushCache.dispose();
    super.dispose();
  }

  void _scheduleRender() {
    if (_throttle != null) return;
    final isDragging = ref.read(isUserDraggingSliderProvider);
    final delay = Duration(milliseconds: isDragging ? 50 : 33);
    _throttle = Timer(delay, () {
      _throttle = null;
      _runRender();
    });
  }

  void _scheduleHighQualityRerender() {
    _throttle?.cancel();
    _throttle = Timer(const Duration(milliseconds: 80), () {
      _throttle = null;
      _runRender();
    });
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
        targetWidth: tw,
        targetHeight: th,
        developCache: _developCache,
        brushCache: _brushCache,
      );

      if (gen != _generation || !mounted) {
        result.dispose();
        return;
      }
      final old = _rendered;
      setState(() => _rendered = result);
      old?.dispose();
    } catch (e) {
      debugPrint('MultiPassPreview render failed: $e');
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
      return const Stack(
        alignment: Alignment.center,
        children: [CircularProgressIndicator(strokeWidth: 2)],
      );
    }
    return RawImage(image: _rendered, fit: BoxFit.contain);
  }
}
