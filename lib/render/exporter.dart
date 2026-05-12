import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img_pkg;

import '../core/models/adjustment_params.dart';
import '../native/raw_bridge.dart';
import 'render_engine.dart';

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
  /// 解码全分辨率 RAW → 转 sRGB-encoded ui.Image → shader 渲染 → 编码 → 写盘
  static Future<File> exportFullRes({
    required String inputRawPath,
    required String outputPath,
    required ExportFormat format,
    required ui.FragmentProgram shaderProgram,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    int jpegQuality = 95,
    ExportProgress? onProgress,
  }) async {
    onProgress?.call(0.05, '解码 RAW（全分辨率）...');
    final raw = await RawBridge.decodeFull(inputRawPath);

    onProgress?.call(0.40, '色彩空间转换...');
    final sourceImage = await _rawToUiImage(raw);

    onProgress?.call(0.65, 'GPU 渲染...');
    final rendered = await RenderEngine.renderToImage(
      program: shaderProgram,
      sourceImage: sourceImage,
      params: params,
      lutTexture: lutTexture,
      lutSize: lutSize,
    );
    sourceImage.dispose();

    onProgress?.call(0.80, '编码 ${format.extension.toUpperCase()}...');
    final Uint8List bytes;
    switch (format) {
      case ExportFormat.png:
        final bd = await rendered.toByteData(format: ui.ImageByteFormat.png);
        bytes = bd!.buffer.asUint8List();
        break;
      case ExportFormat.jpeg:
        final bd = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final w = rendered.width, h = rendered.height;
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
    rendered.dispose();

    onProgress?.call(0.95, '写入文件...');
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    onProgress?.call(1.0, '完成');
    return file;
  }

  // 16-bit linear RGB → sRGB-encoded ui.Image
  static Future<ui.Image> _rawToUiImage(RawDecodedImage raw) async {
    final bytes = await Isolate.run(() {
      final lut = _buildSrgbLut();
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

  static Uint8List _buildSrgbLut() {
    final lut = Uint8List(65536);
    for (int i = 0; i < 65536; i++) {
      final l = i / 65535.0;
      final s = l <= 0.0031308
          ? l * 12.92
          : 1.055 * math.pow(l, 1.0 / 2.4) - 0.055;
      lut[i] = (s.clamp(0.0, 1.0) * 255.0).round();
    }
    return lut;
  }

  static double _pow(double x, double e) {
    return x <= 0 ? 0 : _expHelper(_lnHelper(x) * e);
  }

  static double _lnHelper(double x) {
    return _natLog(x);
  }

  static double _natLog(double x) => _MathStub.log(x);
  static double _expHelper(double x) => _MathStub.exp(x);
}

class _MathStub {
  static double log(double x) => math.log(x);

  static double exp(double x) => math.exp(x);
}
