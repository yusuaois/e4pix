// lib/render/raw_to_ui_image.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../native/raw_bridge.dart';

/// 将 RAW 解码结果转为 Flutter ui.Image（用于上传到 shader）。
/// 16-bit 数据会被压成 8-bit RGBA（预览阶段够用，专业管线可改 Float texture）
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
    // 16-bit linear → 8-bit display（直接 >> 8，下一阶段会替换为 sRGB encode）
    for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
      rgba[j]     = src[i]     >> 8;
      rgba[j + 1] = src[i + 1] >> 8;
      rgba[j + 2] = src[i + 2] >> 8;
      rgba[j + 3] = 255;
    }
  } else if (src is Uint8List) {
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