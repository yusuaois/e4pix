import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/color/srgb_lut.dart';
import '../native/raw_bridge.dart';
import 'cpu_denoise.dart';

/// 像素格式转换：RAW 解码结果（16-bit 线性）→ 8-bit sRGB [ui.Image]
///
/// 所有重活在后台 isolate 完成，主 isolate 仅做 ui.Image 解码回调
class PixelConvert {
  PixelConvert._();

  /// RAW（16-bit 线性）→ 8-bit sRGB ui.Image，无降噪
  static Future<ui.Image> rawToImage(RawDecodedImage raw) async {
    final bytes = await Isolate.run(() {
      final lut = Uint8List.fromList(srgbLut16To8);
      return _convertWithLut(raw, lut);
    });
    return _decode(bytes, raw.width, raw.height);
  }

  /// RAW（16-bit 线性）→ CPU 并行降噪 → 8-bit sRGB ui.Image
  ///
  /// [progressStart]/[progressEnd] 是本步骤在整体导出进度中占据的区间；
  /// 其中前 85% 给降噪、后 15% 给格式转换
  static Future<ui.Image> rawToImageWithDenoise(
    RawDecodedImage raw,
    double luma,
    double color, {
    void Function(double fraction, String stage)? onProgress,
    String denoiseStage = '',
    String convertStage = '',
    double progressStart = 0.0,
    double progressEnd = 1.0,
    int parallelism = 4,
  }) async {
    final src = raw.pixels as Uint16List;
    final w = raw.width, h = raw.height;
    final denoiseEnd = progressStart + (progressEnd - progressStart) * 0.85;

    final denoised = await cpuDenoiseParallel(
      src,
      w,
      h,
      luma,
      color,
      parallelism: parallelism,
      onProgress: (f) => onProgress?.call(
        progressStart + (denoiseEnd - progressStart) * f,
        denoiseStage,
      ),
    );

    onProgress?.call(denoiseEnd, convertStage);
    final rgba = await _convertDenoisedToRgba(denoised, w, h);
    onProgress?.call(progressEnd, convertStage);

    return _decode(rgba, w, h);
  }

  // ── 内部 ──────────────────────────────────────────────────

  static Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
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
  ) {
    return Isolate.run(() => _convert16ToRgba(denoised, w, h));
  }

  /// 16-bit 线性 RGB 交错 → 8-bit sRGB RGBA
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

  /// RAW 像素（16-bit 线性或 8-bit）→ 8-bit sRGB RGBA
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
