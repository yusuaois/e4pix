import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:image/image.dart' as img_pkg;
import 'package:path_provider/path_provider.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/full_pipeline_renderer.dart';

class AIInputRenderer {
  static Future<String> renderToTempFile({
    required ui.FragmentProgram program,
    required ui.FragmentProgram maskProgram,
    required ui.Image sourceImage,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    int maxEdge = 768,
    int jpegQuality = 85,
  }) async {
    final rendered = await FullPipelineRenderer.render(
      developProgram: program,
      maskProgram: maskProgram,
      sourceImage: sourceImage,
      params: params,
      lutTexture: lutTexture,
      lutSize: lutSize,
      targetWidth: sourceImage.width,
      targetHeight: sourceImage.height,
    );

    final byteData =
        await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = rendered.width;
    final h = rendered.height;
    rendered.dispose();
    if (byteData == null) throw Exception('Failed to read rendered RGBA');
    final rgbaBytes = byteData.buffer.asUint8List();

    final jpegBytes = await Isolate.run(() {
      var image = img_pkg.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgbaBytes.buffer,
        order: img_pkg.ChannelOrder.rgba,
      );
      final longest = math.max(w, h);
      if (longest > maxEdge) {
        final scale = maxEdge / longest;
        image = img_pkg.copyResize(
          image,
          width: (w * scale).round(),
          height: (h * scale).round(),
          interpolation: img_pkg.Interpolation.cubic,
        );
      }
      return img_pkg.encodeJpg(image, quality: jpegQuality);
    });

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/e4pix_ai_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(jpegBytes);
    return path;
  }
}