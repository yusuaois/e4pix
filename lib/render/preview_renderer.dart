import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/models/adjustment_params.dart';
import '../state/render/render_state.dart';
import '../state/params/params_state.dart';
import 'develop_uniforms.dart';

class PreviewRenderer extends ConsumerStatefulWidget {
  final ui.Image image;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;

  const PreviewRenderer({
    super.key,
    required this.image,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
  });

  @override
  ConsumerState<PreviewRenderer> createState() => _PreviewRendererState();
}

class _PreviewRendererState extends ConsumerState<PreviewRenderer> {
  ui.FragmentProgram? _cachedProgram;
  ui.FragmentShader? _cachedShader;

  ui.FragmentShader _shaderFor(ui.FragmentProgram program) {
    if (!identical(_cachedProgram, program)) {
      _cachedProgram = program;
      _cachedShader = program.fragmentShader();
    }
    return _cachedShader!;
  }

  @override
  Widget build(BuildContext context) {
    final programAsync = ref.watch(shaderProgramProvider);
    final params = ref.watch(throttledParamsProvider);
    return programAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text(
          'Shader load failed: $e',
          style: const TextStyle(color: AppColors.semanticError),
        ),
      ),
      data: (program) {
        final shader = _shaderFor(program);
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
                    shader: shader,
                    image: widget.image,
                    params: params,
                    lut: widget.lutTexture,
                    lutSize: widget.lutSize,
                    lutB: widget.lutTextureB,
                    lutSizeB: widget.lutSizeB,
                    curve: widget.curveTexture,
                  ),
                ),
              ),
            );
          },
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
  final ui.Image? curve;

  _DevelopPainter({
    required this.shader,
    required this.image,
    required this.params,
    this.lut,
    this.lutSize = 0,
    this.lutB,
    this.lutSizeB = 0,
    this.curve,
  });

  @override
  void paint(Canvas canvas, Size size) {
    try {
      applyDevelopUniforms(
        shader: shader,
        renderSize: size,
        params: params,
        image: image,
        lutTexture: lut,
        lutSize: lutSize,
        lutTextureB: lutB,
        lutSizeB: lutSizeB,
        curveTexture: curve,
      );
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    } catch (e) {
      // 如果 image/lut 已被 dispose，静默跳过本帧渲染，避免崩溃
      // 下一帧 Widget rebuild 会传入新的有效 image
      debugPrint('[PreviewRenderer] Skipping paint due to disposed image: $e');
    }
  }

  @override
  bool shouldRepaint(_DevelopPainter old) =>
      old.image != image ||
      old.params != params ||
      old.lut != lut ||
      old.lutSize != lutSize ||
      old.lutB != lutB ||
      old.lutSizeB != lutSizeB ||
      old.curve != curve;
}
