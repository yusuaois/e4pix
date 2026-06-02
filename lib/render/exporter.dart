import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:isolate';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img_pkg;
import '../core/color/srgb_lut.dart';
import '../core/models/adjustment_params.dart';
import '../native/raw_bridge.dart';
import 'full_pipeline_renderer.dart';

enum ExportFormat { png, jpeg }

enum DenoiseEngine { gpu, cpu }

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
    ui.FragmentProgram? denoiseProgram,
    DenoiseEngine denoiseEngine = DenoiseEngine.cpu,
    int jpegQuality = 95,
    ExportProgress? onProgress,
  }) async {
    onProgress?.call(0.05, tr("exportDecodingImage"));
    final raw = await RawBridge.decodeFull(inputRawPath);

    final wantDenoise =
        params.denoiseLuma > 0.001 || params.denoiseColor > 0.001;
    final useCpuDenoise = wantDenoise && denoiseEngine == DenoiseEngine.cpu;

    final ui.Image sourceImage;
    if (useCpuDenoise) {
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
      // 无降噪 或 GPU 降噪
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
      // GPU 降噪
      denoiseProgram: (wantDenoise && denoiseEngine == DenoiseEngine.gpu)
          ? denoiseProgram
          : null,
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
    final src = raw.pixels as Uint16List;
    final w = raw.width, h = raw.height;

    final denoiseEnd = progressStart + (progressEnd - progressStart) * 0.85;

    // 降噪
    final denoised = await _cpuDenoiseParallel(
      src,
      w,
      h,
      luma,
      color,
      onProgress: (f) => onProgress?.call(
        progressStart + (denoiseEnd - progressStart) * f,
        tr("exportDenoising"),
      ),
    );

    onProgress?.call(denoiseEnd, tr("exportTransformingColorSpace"));

    final rgba = await _convertDenoisedToRgba(denoised, w, h);

    onProgress?.call(progressEnd, tr("exportTransformingColorSpace"));

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Future<Uint8List> _convertDenoisedToRgba(
    Uint16List denoised,
    int w,
    int h,
  ) async {
    return Isolate.run(() => _convert16ToRgba(denoised, w, h));
  }

  // 16-bit 线性 → 8-bit sRGB rgba
  static Uint8List _convert16ToRgba(Uint16List denoised, int w, int h) {
    final lut = Uint8List.fromList(srgbLut16To8);
    final out = Uint8List(w * h * 4);
    final total = w * h;
    for (int i = 0, j = 0; i < total; i++, j += 4) {
      final si = i * 3;
      out[j] = lut[denoised[si]];
      out[j + 1] = lut[denoised[si + 1]];
      out[j + 2] = lut[denoised[si + 2]];
      out[j + 3] = 255;
    }
    return out;
  }

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

// 最大邻域半径（颜色满强度 ±24）
const int _kMaxDenoiseRadius = 24;

// 并行降噪
Future<Uint16List> _cpuDenoiseParallel(
  Uint16List src,
  int w,
  int h,
  double luma,
  double color, {
  required void Function(double) onProgress,
  int parallelism = 4,
}) async {
  int nBands = parallelism <= 0
      ? Platform
            .numberOfProcessors // 0 = 自动
      : parallelism;
  if (nBands > 16) nBands = 16;
  if (nBands < 1) nBands = 1;
  if (h < nBands * (2 * _kMaxDenoiseRadius + 4)) nBands = 1;
  debugPrint('[denoise] nBands=$nBands, prep tasks...');

  final rowsPerBand = (h / nBands).ceil();

  final tasks = <_BandTask>[];
  for (int b = 0; b < nBands; b++) {
    final startRow = b * rowsPerBand;
    if (startRow >= h) continue;
    final endRow = math.min(startRow + rowsPerBand, h);
    final bandRows = endRow - startRow;
    final haloStart = math.max(0, startRow - _kMaxDenoiseRadius);
    final haloEnd = math.min(h, endRow + _kMaxDenoiseRadius);
    final haloTop = startRow - haloStart;
    final totalRows = haloEnd - haloStart;

    final bandLen = totalRows * w * 3;
    final bandPixels = Uint16List(bandLen);
    bandPixels.setRange(0, bandLen, src, haloStart * w * 3);

    tasks.add(
      _BandTask(
        bandId: b,
        pixels: bandPixels,
        width: w,
        totalRows: totalRows,
        bandRows: bandRows,
        haloTop: haloTop,
        luma: luma,
        color: color,
      ),
    );
  }

  // 启动
  final futures = <Future<_BandOut>>[];
  for (final task in tasks) {
    futures.add(_runBandIsolate(task));
  }

  int completed = 0;
  final total = futures.length;
  final outs = <_BandOut>[];
  for (final f in futures) {
    final out = await f;
    outs.add(out);
    completed++;
    onProgress(completed / total);
  }

  final result = Uint16List(w * h * 3);
  outs.sort((a, b) => a.bandId.compareTo(b.bandId));
  int offset = 0;
  for (final o in outs) {
    result.setRange(offset, offset + o.pixels.length, o.pixels);
    offset += o.pixels.length;
  }
  return result;
}

Future<_BandOut> _runBandIsolate(_BandTask task) {
  return Isolate.run(() => _denoiseBandTask(task));
}

class _BandTask {
  final int bandId;
  final Uint16List pixels;
  final int width;
  final int totalRows;
  final int bandRows;
  final int haloTop;
  final double luma;
  final double color;
  _BandTask({
    required this.bandId,
    required this.pixels,
    required this.width,
    required this.totalRows,
    required this.bandRows,
    required this.haloTop,
    required this.luma,
    required this.color,
  });
}

class _BandOut {
  final int bandId;
  final Uint16List pixels;
  _BandOut(this.bandId, this.pixels);
}

_BandOut _denoiseBandTask(_BandTask t) {
  final denoised = _cpuDenoise16(
    t.pixels,
    t.width,
    t.totalRows,
    t.luma,
    t.color,
  );
  final result = Uint16List(t.width * t.bandRows * 3);
  result.setRange(0, result.length, denoised, t.haloTop * t.width * 3);
  return _BandOut(t.bandId, result);
}

// 16-bit 线性 RGB 交错 → 降噪 → 16-bit 线性 RGB 交错
Uint16List _cpuDenoise16(
  Uint16List src,
  int w,
  int h,
  double luma,
  double color, {
  void Function(double)? onProgress,
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

  final sigmaY = _lerp(0.003, 0.05, luma);
  final sigmaC = _lerp(0.02, 0.35, color);
  const int RY = 2;
  final double radiusC = _lerp(6.0, 24.0, color);
  final int stepsC = 4;
  final double stepC = radiusC / stepsC;
  final double spatialY2 = 4.0;
  final double spatialC2 = radiusC * radiusC * 0.35;

  // 预计算 exp 衰减查找表
  const int kLutSize = 2048;
  const double kLutMax = 10.0;
  final expLut = Float32List(kLutSize);
  for (int i = 0; i < kLutSize; i++) {
    expLut[i] = math.exp(-(i / kLutSize) * kLutMax);
  }

  // 预计算明度空间权重 (5x5)
  final int wy = 2 * RY + 1;
  final spatialYLut = Float32List(wy * wy);
  {
    int k = 0;
    for (int dy = -RY; dy <= RY; dy++) {
      for (int dx = -RY; dx <= RY; dx++) {
        spatialYLut[k++] = math.exp(-(dx * dx + dy * dy) / (2.0 * spatialY2));
      }
    }
  }

  // 预计算颜色空间权重 + 整数偏移 (9x9)
  final int wc = 2 * stepsC + 1;
  final spatialCLut = Float32List(wc * wc);
  final offCx = Int32List(wc * wc);
  final offCy = Int32List(wc * wc);
  {
    int k = 0;
    for (int sy = -stepsC; sy <= stepsC; sy++) {
      for (int sx = -stepsC; sx <= stepsC; sx++) {
        final ox = sx * stepC, oy = sy * stepC;
        spatialCLut[k] = math.exp(-(ox * ox + oy * oy) / (2.0 * spatialC2));
        offCx[k] = ox.round();
        offCy[k] = oy.round();
        k++;
      }
    }
  }

  // range 权重的归一化系数（把 d² 映射到 LUT 索引）
  final double invDenomY = 1.0 / (2.0 * sigmaY * sigmaY);
  final double invDenomC = 1.0 / (2.0 * sigmaC * sigmaC);
  final double lutScale = kLutSize / kLutMax;

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
        int k = 0;
        for (int dy = -RY; dy <= RY; dy++) {
          final yy = y0 + dy;
          for (int dx = -RY; dx <= RY; dx++) {
            final xx = x0 + dx;
            if (yy < 0 || yy >= h || xx < 0 || xx >= w) {
              k++;
              continue;
            }
            final si = yy * w + xx;
            final spatial = spatialYLut[k++];
            final dY = Y[si] - cY;
            // range 查表
            final e = dY * dY * invDenomY * lutScale;
            final range = e >= kLutSize ? 0.0 : expLut[e.toInt()];
            final wgt = spatial * range;
            acc += Y[si] * wgt;
            sum += wgt;
          }
        }
        outY[ci] = sum > 0 ? cY + (acc / sum - cY) * luma : cY;
      } else {
        outY[ci] = cY;
      }

      // 颜色 9x9 稀疏
      if (doColor) {
        double accCb = 0, accCr = 0, sum = 0;
        for (int k = 0; k < wc * wc; k++) {
          final yy = y0 + offCy[k];
          final xx = x0 + offCx[k];
          if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue;
          final si = yy * w + xx;
          final spatial = spatialCLut[k];
          final dCb = Cb[si] - cCb, dCr = Cr[si] - cCr;
          final e = (dCb * dCb + dCr * dCr) * invDenomC * lutScale;
          final range = e >= kLutSize ? 0.0 : expLut[e.toInt()];
          final wgt = spatial * range;
          accCb += Cb[si] * wgt;
          accCr += Cr[si] * wgt;
          sum += wgt;
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
    if ((y0 & 0x1F) == 0) onProgress?.call(y0 / h);
  }

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
int _clamp16(double v) {
  final i = (v * 65535.0).round();
  return i < 0 ? 0 : (i > 65535 ? 65535 : i);
}
