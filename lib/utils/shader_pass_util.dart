import 'dart:ui' as ui;

/// 通用 GPU 着色器单 pass 执行工具
///
/// fragmentShader → set uniforms → PictureRecorder → drawRect → toImage
Future<ui.Image> runSingleShaderPass({
  required ui.FragmentShader shader,
  required int outputWidth,
  required int outputHeight,
  required void Function(ui.FragmentShader shader) setUniforms,
  required List<ui.Image> samplers,
}) async {
  for (int i = 0; i < samplers.length; i++) {
    shader.setImageSampler(i, samplers[i]);
  }
  setUniforms(shader);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(outputWidth, outputHeight);
  } finally {
    picture.dispose();
  }
}
