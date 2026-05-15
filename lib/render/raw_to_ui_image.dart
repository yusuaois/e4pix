import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/color/srgb_lut.dart';
import '../native/raw_bridge.dart';

// 预览图的长边上限
//  `maxEdge: -1`
const int kPreviewMaxEdge = 2400;
Future<ui.Image> rawToUiImage(
  RawDecodedImage raw, {
  int maxEdge = kPreviewMaxEdge,
}) async {
  if (raw.isJpegEncoded) {
    final codec = await ui.instantiateImageCodec(raw.pixels as Uint8List);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  final srcW = raw.width;
  final srcH = raw.height;

  // 目标尺寸
  final int tgtW;
  final int tgtH;
  if (maxEdge > 0 && math.max(srcW, srcH) > maxEdge) {
    final scale = maxEdge / math.max(srcW, srcH);
    tgtW = (srcW * scale).round();
    tgtH = (srcH * scale).round();
  } else {
    tgtW = srcW;
    tgtH = srcH;
  }

  // downsample + LUT 转换在 isolate 中执行
  final pixels = raw.pixels;
  final rgba = await Isolate.run(() {
    return _convertInIsolate(pixels, srcW, srcH, tgtW, tgtH);
  });

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    tgtW,
    tgtH,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}


// Isolate 内实现渲染
Uint8List _convertInIsolate(TypedData src, int sw, int sh, int tw, int th) {
  final out = Uint8List(tw * th * 4);
  final needScale = (sw != tw || sh != th);

  if (src is Uint16List) {
    final lut = srgbLut16To8;
    if (needScale) {
      _boxDownsample16ToSrgb8(src, sw, sh, tw, th, out, lut);
    } else {
      _copy16ToSrgb8(src, out, lut);
    }
  } else if (src is Uint8List) {
    if (needScale) {
      _boxDownsample8(src, sw, sh, tw, th, out);
    } else {
      _copy8(src, out);
    }
  }
  return out;
}

// 不缩放
void _copy16ToSrgb8(Uint16List src, Uint8List out, Uint8List lut) {
  for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
    out[j] = lut[src[i]];
    out[j + 1] = lut[src[i + 1]];
    out[j + 2] = lut[src[i + 2]];
    out[j + 3] = 255;
  }
}

void _copy8(Uint8List src, Uint8List out) {
  for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
    out[j] = src[i];
    out[j + 1] = src[i + 1];
    out[j + 2] = src[i + 2];
    out[j + 3] = 255;
  }
}

// 缩放
void _boxDownsample16ToSrgb8(
  Uint16List src,
  int sw,
  int sh,
  int tw,
  int th,
  Uint8List out,
  Uint8List lut,
) {
  final scaleX = sw / tw;
  final scaleY = sh / th;

  for (int y = 0; y < th; y++) {
    final ySrcStart = (y * scaleY).floor();
    int ySrcEnd = ((y + 1) * scaleY).ceil();
    if (ySrcEnd <= ySrcStart) ySrcEnd = ySrcStart + 1;
    if (ySrcEnd > sh) ySrcEnd = sh;

    final outRowBase = y * tw * 4;

    for (int x = 0; x < tw; x++) {
      final xSrcStart = (x * scaleX).floor();
      int xSrcEnd = ((x + 1) * scaleX).ceil();
      if (xSrcEnd <= xSrcStart) xSrcEnd = xSrcStart + 1;
      if (xSrcEnd > sw) xSrcEnd = sw;

      int sumR = 0, sumG = 0, sumB = 0, count = 0;

      for (int yy = ySrcStart; yy < ySrcEnd; yy++) {
        final rowBase = yy * sw * 3;
        for (int xx = xSrcStart; xx < xSrcEnd; xx++) {
          final idx = rowBase + xx * 3;
          sumR += src[idx];
          sumG += src[idx + 1];
          sumB += src[idx + 2];
          count++;
        }
      }

      final outIdx = outRowBase + x * 4;
      out[outIdx] = lut[sumR ~/ count];
      out[outIdx + 1] = lut[sumG ~/ count];
      out[outIdx + 2] = lut[sumB ~/ count];
      out[outIdx + 3] = 255;
    }
  }
}

void _boxDownsample8(
  Uint8List src,
  int sw,
  int sh,
  int tw,
  int th,
  Uint8List out,
) {
  final scaleX = sw / tw;
  final scaleY = sh / th;

  for (int y = 0; y < th; y++) {
    final ySrcStart = (y * scaleY).floor();
    int ySrcEnd = ((y + 1) * scaleY).ceil();
    if (ySrcEnd <= ySrcStart) ySrcEnd = ySrcStart + 1;
    if (ySrcEnd > sh) ySrcEnd = sh;

    final outRowBase = y * tw * 4;

    for (int x = 0; x < tw; x++) {
      final xSrcStart = (x * scaleX).floor();
      int xSrcEnd = ((x + 1) * scaleX).ceil();
      if (xSrcEnd <= xSrcStart) xSrcEnd = xSrcStart + 1;
      if (xSrcEnd > sw) xSrcEnd = sw;

      int sumR = 0, sumG = 0, sumB = 0, count = 0;

      for (int yy = ySrcStart; yy < ySrcEnd; yy++) {
        final rowBase = yy * sw * 3;
        for (int xx = xSrcStart; xx < xSrcEnd; xx++) {
          final idx = rowBase + xx * 3;
          sumR += src[idx];
          sumG += src[idx + 1];
          sumB += src[idx + 2];
          count++;
        }
      }

      final outIdx = outRowBase + x * 4;
      out[outIdx] = sumR ~/ count;
      out[outIdx + 1] = sumG ~/ count;
      out[outIdx + 2] = sumB ~/ count;
      out[outIdx + 3] = 255;
    }
  }
}
