import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:isolate';
import 'package:easy_localization/easy_localization.dart';
import 'package:image/image.dart' as img_pkg;
import '../core/color/srgb_lut.dart';
import '../core/models/adjustment_params.dart';
import '../native/raw_bridge.dart';
import 'full_pipeline_renderer.dart';


enum ExportFormat { png, jpeg }

extension ExportFormatExt on ExportFormat {
  String get extension => switch (this) {
    ExportFormat.png => 'png',
    ExportFormat.jpeg => 'jpg',
  };
}

typedef ExportProgress = void Function(double fraction, String stage);

class Exporter {
  /// 全分辨率导出
  static Future<File> exportFullRes({
    required String inputRawPath,
    required String outputPath,
    required ExportFormat format,
    required ui.FragmentProgram shaderProgram,
    required ui.FragmentProgram maskProgram,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    ui.Image? lutTextureB,
    int lutSizeB = 0,
    int jpegQuality = 95,
    ExportProgress? onProgress,
  }) async {
    onProgress?.call(0.05, tr("exportDecodingImage"));
    final raw = await RawBridge.decodeFull(inputRawPath);

    onProgress?.call(0.40, tr("exportTransformingColorSpace"));
    final sourceImage = await _rawToUiImage(raw);

    onProgress?.call(0.65, tr("exportRenderingImage"));

    final output = await FullPipelineRenderer.render(
      developProgram: shaderProgram,
      maskProgram: maskProgram,
      sourceImage: sourceImage,
      params: params,
      lutTexture: lutTexture,
      lutSize: lutSize,
      lutTextureB: lutTextureB,
      lutSizeB: lutSizeB,
      targetWidth: sourceImage.width,
      targetHeight: sourceImage.height,
    );
    sourceImage.dispose();

    onProgress?.call(
      0.80,
      tr("exportEncodingImage", args: [format.extension.toUpperCase()]),
    );
    final Uint8List bytes;
    switch (format) {
      case ExportFormat.png:
        final bd = await output.toByteData(format: ui.ImageByteFormat.png);
        bytes = bd!.buffer.asUint8List();
        break;
      case ExportFormat.jpeg:
        final bd = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
        final w = output.width, h = output.height;
        bytes = await Isolate.run(() {
          final image = img_pkg.Image.fromBytes(
            width: w,
            height: h,
            bytes: bd!.buffer,
            order: img_pkg.ChannelOrder.rgba,
          );
          return img_pkg.encodeJpg(image, quality: jpegQuality);
        });
        break;
    }
    output.dispose();

    onProgress?.call(0.95, tr("writingFile"));
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    onProgress?.call(1.0, tr("completed"));
    return file;
  }

  // 16-bit linear RGB → sRGB-encoded ui.Image
  static Future<ui.Image> _rawToUiImage(RawDecodedImage raw) async {
    final bytes = await Isolate.run(() {
      final lutCopy = Uint8List.fromList(srgbLut16To8);
      return _convertWithLut(raw, lutCopy);
    });

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      raw.width,
      raw.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Uint8List _convertWithLut(RawDecodedImage raw, Uint8List lut) {
    final src = raw.pixels;
    final w = raw.width, h = raw.height;
    final rgba = Uint8List(w * h * 4);
    if (src is Uint16List) {
      for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
        rgba[j] = lut[src[i]];
        rgba[j + 1] = lut[src[i + 1]];
        rgba[j + 2] = lut[src[i + 2]];
        rgba[j + 3] = 255;
      }
    } else if (src is Uint8List) {
      for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
        rgba[j] = src[i];
        rgba[j + 1] = src[i + 1];
        rgba[j + 2] = src[i + 2];
        rgba[j + 3] = 255;
      }
    }
    return rgba;
  }
}
