import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../state/interaction_state.dart';
import 'develop_uniforms.dart';

class PreviewRenderer extends ConsumerStatefulWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;

  const PreviewRenderer({
    super.key,
    required this.image,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
  });

  @override
  ConsumerState<PreviewRenderer> createState() => _PreviewRendererState();
}

class _PreviewRendererState extends ConsumerState<PreviewRenderer> {
  ui.FragmentShader? _shader;
  Object? _shaderError;

  late AdjustmentParams _displayedParams;
  Timer? _throttle;
  ProviderSubscription<bool>? _dragSub;

  static const _draggingInterval = Duration(milliseconds: 33);

  @override
  void initState() {
    super.initState();
    _displayedParams = widget.params;
    _load();

    _dragSub = ref.listenManual<bool>(isUserDraggingSliderProvider, (
      prev,
      next,
    ) {
      if (prev == true && next == false) {
        _throttle?.cancel();
        _throttle = null;
        if (mounted && _displayedParams != widget.params) {
          setState(() => _displayedParams = widget.params);
        }
      }
    });
  }

  @override
  void didUpdateWidget(PreviewRenderer old) {
    super.didUpdateWidget(old);

    if (old.params == widget.params) return;

    final isDragging = ref.read(isUserDraggingSliderProvider);
    if (!isDragging) {
      _throttle?.cancel();
      _throttle = null;
      _displayedParams = widget.params;
      return;
    }

    if (_throttle != null) return;
    _throttle = Timer(_draggingInterval, () {
      _throttle = null;
      if (!mounted) return;
      if (_displayedParams != widget.params) {
        setState(() => _displayedParams = widget.params);
      }
    });
  }

  Future<void> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/develop.frag',
      );
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (e) {
      if (!mounted) return;
      setState(() => _shaderError = e);
    }
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _dragSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shaderError != null) {
      return Center(
        child: Text(
          'Shader load failed: $_shaderError',
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }
    if (_shader == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final imgW = widget.image.width.toDouble();
        final imgH = widget.image.height.toDouble();
        final fit = applyBoxFit(
          BoxFit.contain,
          Size(imgW, imgH),
          constraints.biggest,
        );
        return Center(
          child: SizedBox.fromSize(
            size: fit.destination,
            child: CustomPaint(
              painter: _DevelopPainter(
                shader: _shader!,
                image: widget.image,
                params: _displayedParams,
                lut: widget.lutTexture,
                lutSize: widget.lutSize,
                lutB: widget.lutTextureB,
                lutSizeB: widget.lutSizeB,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DevelopPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lut;
  final int lutSize;
  final ui.Image? lutB;
  final int lutSizeB;

  _DevelopPainter({
    required this.shader,
    required this.image,
    required this.params,
    this.lut,
    this.lutSize = 0,
    this.lutB,
    this.lutSizeB = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    applyDevelopUniforms(
      shader: shader,
      renderSize: size,
      params: params,
      image: image,
      lutTexture: lut,
      lutSize: lutSize,
      lutTextureB: lutB,
      lutSizeB: lutSizeB,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DevelopPainter old) =>
      old.image != image ||
      old.params != params ||
      old.lut != lut ||
      old.lutSize != lutSize ||
      old.lutB != lutB ||
      old.lutSizeB != lutSizeB;
}
