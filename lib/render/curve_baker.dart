import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/models/rgb_curves.dart';

/// 把 [RgbCurves] 烤成 256×5 RGBA 纹理。
/// 行 0=主 1=R 2=G 3=B 4=亮度。identity 返回 null（无需纹理）。
///
/// 纯函数：不依赖任何 Notifier / 全局状态。供 CurveTextureNotifier（预览）
/// 和 Exporter（每张图按自身 params.curves 现生成）共用，保证批量导出
/// 每张图用各自的曲线。
Future<ui.Image?> bakeCurveTexture(RgbCurves curves) async {
  if (curves.isIdentity) return null;

  final master = curves.master.toLut(count: 256);
  final r = curves.red.toLut(count: 256);
  final g = curves.green.toLut(count: 256);
  final b = curves.blue.toLut(count: 256);
  final lum = curves.luminance.toLut(count: 256);

  final pixels = Uint8List(256 * 5 * 4); // w * h * rgba
  void writeRow(int row, Float32List lut) {
    for (int x = 0; x < 256; x++) {
      final idx = (row * 256 + x) * 4;
      final v = (lut[x] * 255).round().clamp(0, 255);
      pixels[idx] = v;
      pixels[idx + 1] = v;
      pixels[idx + 2] = v;
      pixels[idx + 3] = 255;
    }
  }

  writeRow(0, master);
  writeRow(1, r);
  writeRow(2, g);
  writeRow(3, b);
  writeRow(4, lum);

  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, 256, 5, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}