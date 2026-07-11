import 'dart:ui' as ui;

/// 纹理已被 dispose 时抛出，调用方可跳过本帧渲染
class DisposedImageException implements Exception {
  final String message;
  const DisposedImageException([this.message = 'Image has been disposed']);
  @override
  String toString() => 'DisposedImageException: $message';
}

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
    final img = samplers[i];
    try {
      shader.setImageSampler(i, img);
    } on AssertionError catch (e) {
      int? w, h;
      try {
        w = img.width;
        h = img.height;
      } catch (_) {}
      throw DisposedImageException(
        'sampler[$i] hash=${identityHashCode(img)} w=${w ?? '?'} h=${h ?? '?'} '
        'msg=${e.message}',
      );
    }
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
    final result = await picture.toImage(outputWidth, outputHeight);
    return result;
  } finally {
    picture.dispose();
  }
}
