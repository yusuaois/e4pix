import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models/adjustment_params.dart';
import '../render/full_pipeline_renderer.dart';

/// 离屏多 pass 预览。当 params.locals 包含启用的局部调整时使用。
/// 不应该跟普通 PreviewRenderer 同时使用——上层 widget 二选一。
class MultiPassPreview extends StatefulWidget {
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final int maxEdge;

  const MultiPassPreview({
    super.key,
    required this.developProgram,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.maxEdge = 2400,
  });

  @override
  State<MultiPassPreview> createState() => _MultiPassPreviewState();
}

class _MultiPassPreviewState extends State<MultiPassPreview> {
  ui.Image? _rendered;
  int _generation = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
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
    _debounce?.cancel();
    _rendered?.dispose();
    super.dispose();
  }

  void _scheduleRender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 33), _runRender);
  }

  Future<void> _runRender() async {
    final gen = ++_generation;
    final src = widget.sourceImage;

    final longest = math.max(src.width, src.height);
    final scale = longest > widget.maxEdge ? widget.maxEdge / longest : 1.0;
    final tw = (src.width * scale).round();
    final th = (src.height * scale).round();

    try {
      final result = await FullPipelineRenderer.render(
        developProgram: widget.developProgram,
        maskProgram: widget.maskProgram,
        sourceImage: src,
        params: widget.params,
        lutTexture: widget.lutTexture,
        lutSize: widget.lutSize,
        targetWidth: tw,
        targetHeight: th,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rendered == null) {
      return Stack(
        alignment: Alignment.center,
        children: const [
          CircularProgressIndicator(strokeWidth: 2),
        ],
      );
    }
    return RawImage(image: _rendered, fit: BoxFit.contain);
  }
}