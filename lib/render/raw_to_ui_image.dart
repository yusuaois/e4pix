import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/color/srgb_lut.dart';
import '../native/raw_bridge.dart';

/// RAW 解码结果 → sRGB-encoded ui.Image（develop shader 的标准输入约定）。
///
/// LibRaw 在我们的 e4pix_decode_preview / e4pix_decode_full 配置中输出
/// 16-bit linear-light（gamma=1, no_auto_bright=1, sRGB primaries）。
/// 这里必须把 linear → sRGB-encoded，与 Exporter 内部转换一致，才能保证
/// 屏幕预览、AI 输入、最终导出三者颜色一致。
Future<ui.Image> rawToUiImage(RawDecodedImage raw) async {
  // 内嵌缩略图本身就是 sRGB JPEG，原样解
  if (raw.isJpegEncoded) {
    final codec = await ui.instantiateImageCodec(raw.pixels as Uint8List);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  final src = raw.pixels;
  final w = raw.width, h = raw.height;
  final rgba = Uint8List(w * h * 4);

  if (src is Uint16List) {
    // 16-bit linear → 8-bit sRGB-encoded
    final lut = srgbLut16To8;
    for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
      rgba[j]     = lut[src[i]];
      rgba[j + 1] = lut[src[i + 1]];
      rgba[j + 2] = lut[src[i + 2]];
      rgba[j + 3] = 255;
    }
  } else if (src is Uint8List) {
    // 8-bit 路径（如某些 bitmap 缩略图）—— 假设已经是 sRGB-encoded
    for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
      rgba[j]     = src[i];
      rgba[j + 1] = src[i + 1];
      rgba[j + 2] = src[i + 2];
      rgba[j + 3] = 255;
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba, w, h, ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}