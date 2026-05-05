import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';

class PreviewRenderer extends StatefulWidget {
  final ui.Image image;
  final AdjustmentParams params;
  const PreviewRenderer({super.key, required this.image, required this.params});

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
      final program = await ui.FragmentProgram.fromAsset('shaders/develop.frag');
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
        child: Text('Shader load failed: $_shaderError',
            style: const TextStyle(color: Colors.redAccent)));
    }
    if (_shader == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 保持原图比例缩放到容器内
        final imgW = widget.image.width.toDouble();
        final imgH = widget.image.height.toDouble();
        final fit = applyBoxFit(BoxFit.contain,
            Size(imgW, imgH), constraints.biggest);
        return Center(
          child: SizedBox.fromSize(
            size: fit.destination,
            child: CustomPaint(
              painter: _DevelopPainter(
                shader: _shader!,
                image: widget.image,
                params: widget.params,
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
  _DevelopPainter({required this.shader, required this.image, required this.params});

  @override
  void paint(Canvas canvas, Size size) {
    final p = params;
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
    shader.setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DevelopPainter old) =>
      old.image != image || old.params != params;
}