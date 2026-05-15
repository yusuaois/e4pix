import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/color/srgb_lut.dart';
import '../native/raw_bridge.dart';

/// sRGB-encoded ui.Image
/// 16-bit linear-light（gamma=1, no_auto_bright=1, sRGB primaries）。
Future<ui.Image> rawToUiImage(RawDecodedImage raw) async {
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