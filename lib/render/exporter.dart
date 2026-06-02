import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
    ui.Image? curveTexture,
    ui.FragmentProgram? sharpenProgram,
    int jpegQuality = 95,
    ExportProgress? onProgress,
  }) async {
    onProgress?.call(0.05, tr("exportDecodingImage"));
    final raw = await RawBridge.decodeFull(inputRawPath);

    final wantDenoise =
        params.denoiseLuma > 0.001 || params.denoiseColor > 0.001;
    final ui.Image sourceImage;
    if (wantDenoise) {
      // CPU 16-bit 线性降噪 + 转换
      sourceImage = await _rawToUiImageWithDenoise(
        raw,
        params.denoiseLuma / 100.0,
        params.denoiseColor / 100.0,
        onProgress,
        0.10,
        0.78,
      );
    } else {
      // 无降噪
      onProgress?.call(0.40, tr("exportTransformingColorSpace"));
      sourceImage = await _rawToUiImage(raw);
    }

    onProgress?.call(0.80, tr("exportRenderingImage"));
    final output = await FullPipelineRenderer.render(
      developProgram: shaderProgram,
      maskProgram: maskProgram,
      sourceImage: sourceImage,
      params: params,
      lutTexture: lutTexture,
      lutSize: lutSize,
      lutTextureB: lutTextureB,
      lutSizeB: lutSizeB,
      curveTexture: curveTexture,
      sharpenProgram: sharpenProgram,
      targetWidth: sourceImage.width,
      targetHeight: sourceImage.height,
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

  static Future<ui.Image> _rawToUiImageWithDenoise(
    RawDecodedImage raw,
    double luma,
    double color,
    ExportProgress? onProgress,
    double progressStart,
    double progressEnd,
  ) async {
    final receivePort = ReceivePort();
    final completer = Completer<Uint8List>();

    receivePort.listen((msg) {
      if (msg is double) {
        // 转换进度
        onProgress?.call(
          progressStart + (progressEnd - progressStart) * msg,
          tr("exportDenoising"),
        );
      } else if (msg is Uint8List) {
        completer.complete(msg);
        receivePort.close();
      }
    });

    await Isolate.spawn(
      _denoiseConvertIsolate,
      _DenoiseConvertParams(
        sendPort: receivePort.sendPort,
        pixels: raw.pixels as Uint16List,
        width: raw.width,
        height: raw.height,
        channels: raw.channels,
        luma: luma,
        color: color,
        srgbLut: Uint8List.fromList(srgbLut16To8),
      ),
    );

    final rgba = await completer.future;

    final imgCompleter = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      raw.width,
      raw.height,
      ui.PixelFormat.rgba8888,
      imgCompleter.complete,
    );
    return imgCompleter.future;
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

// 传给 isolate 的参数包
class _DenoiseConvertParams {
  final SendPort sendPort;
  final Uint16List pixels; // 16-bit RGB 交错线性
  final int width;
  final int height;
  final int channels;
  final double luma; // 0-1
  final double color; // 0-1
  final Uint8List srgbLut; // 16→8 sRGB 查表

  _DenoiseConvertParams({
    required this.sendPort,
    required this.pixels,
    required this.width,
    required this.height,
    required this.channels,
    required this.luma,
    required this.color,
    required this.srgbLut,
  });
}

// 降噪（16-bit 线性）→ 转 8-bit sRGB → 回传
void _denoiseConvertIsolate(_DenoiseConvertParams p) {
  final send = p.sendPort;
  final w = p.width, h = p.height;
  final src = p.pixels;

  // 进度
  void progress(double f) => send.send(f);

  // 降噪 Uint16List
  final denoised = _cpuDenoise16(
    src,
    w,
    h,
    p.luma,
    p.color,
    onProgress: (f) => progress(f * 0.85),
  );

  // 8-bit sRGB rgba
  final lut = p.srgbLut;
  final rgba = Uint8List(w * h * 4);
  final total = w * h;
  for (int i = 0, j = 0; i < total; i++, j += 4) {
    final si = i * 3;
    rgba[j] = lut[denoised[si]];
    rgba[j + 1] = lut[denoised[si + 1]];
    rgba[j + 2] = lut[denoised[si + 2]];
    rgba[j + 3] = 255;
    if ((i & 0x3FFFF) == 0) progress(0.85 + 0.15 * (i / total));
  }

  send.send(rgba);
}

// 16-bit 线性 RGB 交错 → 降噪 → 16-bit 线性 RGB 交错
Uint16List _cpuDenoise16(
  Uint16List src,
  int w,
  int h,
  double luma,
  double color, {
  required void Function(double) onProgress,
}) {
  final out = Uint16List(src.length);
  final n = w * h;

  final Y = Float32List(n);
  final Cb = Float32List(n);
  final Cr = Float32List(n);
  const inv = 1.0 / 65535.0;
  for (int i = 0; i < n; i++) {
    final si = i * 3;
    final r = src[si] * inv;
    final g = src[si + 1] * inv;
    final b = src[si + 2] * inv;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    Y[i] = y;
    Cb[i] = (b - y) * 0.5389 + 0.5;
    Cr[i] = (r - y) * 0.6350 + 0.5;
  }

  // sigma线性域
  final sigmaY = _lerp(0.003, 0.05, luma);
  final sigmaC = _lerp(0.02, 0.35, color);

  // 半径
  const int RY = 2; // 明度 5x5
  final double radiusC = _lerp(6.0, 24.0, color); // 颜色半径，满强度 ±24
  final int stepsC = 4; // 颜色稀疏 9x9
  final double stepC = radiusC / stepsC;
  final double spatialY2 = 4.0; // 明度空间 sigma^2
  final double spatialC2 = radiusC * radiusC * 0.35;

  final outY = Float32List(n);
  final outCb = Float32List(n);
  final outCr = Float32List(n);

  final doLuma = luma > 0.001;
  final doColor = color > 0.001;

  for (int y0 = 0; y0 < h; y0++) {
    for (int x0 = 0; x0 < w; x0++) {
      final ci = y0 * w + x0;
      final cY = Y[ci], cCb = Cb[ci], cCr = Cr[ci];

      // 明度 5x5
      if (doLuma) {
        double acc = 0, sum = 0;
        for (int dy = -RY; dy <= RY; dy++) {
          final yy = y0 + dy;
          if (yy < 0 || yy >= h) continue;
          for (int dx = -RY; dx <= RY; dx++) {
            final xx = x0 + dx;
            if (xx < 0 || xx >= w) continue;
            final si = yy * w + xx;
            final spatial = _expf(-(dx * dx + dy * dy) / (2.0 * spatialY2));
            final dY = Y[si] - cY;
            final range = _expf(-(dY * dY) / (2.0 * sigmaY * sigmaY));
            final wgt = spatial * range;
            acc += Y[si] * wgt;
            sum += wgt;
          }
        }
        outY[ci] = sum > 0 ? cY + (acc / sum - cY) * luma : cY;
      } else {
        outY[ci] = cY;
      }

      // 颜色
      if (doColor) {
        double accCb = 0, accCr = 0, sum = 0;
        for (int sy = -stepsC; sy <= stepsC; sy++) {
          final yy = (y0 + (sy * stepC)).round();
          if (yy < 0 || yy >= h) continue;
          for (int sx = -stepsC; sx <= stepsC; sx++) {
            final xx = (x0 + (sx * stepC)).round();
            if (xx < 0 || xx >= w) continue;
            final si = yy * w + xx;
            final ox = sx * stepC, oy = sy * stepC;
            final spatial = _expf(-(ox * ox + oy * oy) / (2.0 * spatialC2));
            final dCb = Cb[si] - cCb, dCr = Cr[si] - cCr;
            final range = _expf(
              -(dCb * dCb + dCr * dCr) / (2.0 * sigmaC * sigmaC),
            );
            final wgt = spatial * range;
            accCb += Cb[si] * wgt;
            accCr += Cr[si] * wgt;
            sum += wgt;
          }
        }
        if (sum > 0) {
          outCb[ci] = cCb + (accCb / sum - cCb) * color;
          outCr[ci] = cCr + (accCr / sum - cCr) * color;
        } else {
          outCb[ci] = cCb;
          outCr[ci] = cCr;
        }
      } else {
        outCb[ci] = cCb;
        outCr[ci] = cCr;
      }
    }
    if ((y0 & 0x1F) == 0) onProgress(y0 / h); // 每 32 行更新进度
  }

  // YCbCr → RGB → 16-bit
  for (int i = 0; i < n; i++) {
    final yv = outY[i];
    final cb = outCb[i] - 0.5;
    final cr = outCr[i] - 0.5;
    double r = yv + cr * 1.5748;
    double b = yv + cb * 1.8556;
    double g = (yv - 0.2126 * r - 0.0722 * b) / 0.7152;
    final si = i * 3;
    out[si] = _clamp16(r);
    out[si + 1] = _clamp16(g);
    out[si + 2] = _clamp16(b);
  }
  return out;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _expf(double x) => math.exp(x);
int _clamp16(double v) {
  final i = (v * 65535.0).round();
  return i < 0 ? 0 : (i > 65535 ? 65535 : i);
}
