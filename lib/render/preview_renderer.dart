import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';

class PreviewRenderer extends StatefulWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lutTexture; // ← 新增
  final int lutSize; // ← 新增（0 表示无 LUT）

  const PreviewRenderer({
    super.key,
    required this.image,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
  });

  @override
  State<PreviewRenderer> createState() => _PreviewRendererState();
}

class _PreviewRendererState extends State<PreviewRenderer> {
  ui.FragmentShader? _shader;
  Object? _shaderError;

  @override
  void initState() {
    super.initState();
    _load();
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
        // 保持原图比例缩放到容器内
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
                params: widget.params,
                lut: widget.lutTexture,
                lutSize: widget.lutSize,
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

  _DevelopPainter({
    required this.shader,
    required this.image,
    required this.params,
    this.lut,
    this.lutSize = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = params;
    final h = p.hsl;
    int i = 0;
    shader.setFloat(i++, size.width);
    shader.setFloat(i++, size.height);
    shader.setFloat(i++, p.exposure);
    shader.setFloat(i++, ((p.temperature - 5500) / 4500).clamp(-1.0, 1.0));
    shader.setFloat(i++, p.tint / 100.0);
    shader.setFloat(i++, p.contrast / 100.0);
    shader.setFloat(i++, p.highlights / 100.0);
    shader.setFloat(i++, p.shadows / 100.0);
    shader.setFloat(i++, p.whites / 100.0);
    shader.setFloat(i++, p.blacks / 100.0);
    shader.setFloat(i++, p.saturation / 100.0);
    shader.setFloat(i++, p.vibrance / 100.0);

    // HSL 24
    for (int k = 0; k < 4; k++) shader.setFloat(i++, h.hues[k] / 100.0);
    for (int k = 4; k < 8; k++) shader.setFloat(i++, h.hues[k] / 100.0);
    for (int k = 0; k < 4; k++) shader.setFloat(i++, h.sats[k] / 100.0);
    for (int k = 4; k < 8; k++) shader.setFloat(i++, h.sats[k] / 100.0);
    for (int k = 0; k < 4; k++) shader.setFloat(i++, h.lums[k] / 100.0);
    for (int k = 4; k < 8; k++) shader.setFloat(i++, h.lums[k] / 100.0);

    // ---- LUT (36-38) ----
    final hasLut = lut != null && lutSize > 0;
    shader.setFloat(i++, hasLut ? p.lutIntensity : 0.0);
    shader.setFloat(i++, lutSize.toDouble());
    shader.setFloat(i++, hasLut ? 1.0 : 0.0);

    shader.setImageSampler(0, image);
    // sampler 1：LUT 必须始终绑一个图（即便不用），否则 shader 会崩
    shader.setImageSampler(1, lut ?? image);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DevelopPainter old) =>
      old.image != image ||
      old.params != params ||
      old.lut != lut ||
      old.lutSize != lutSize;
}
