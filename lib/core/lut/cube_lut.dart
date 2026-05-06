import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

class CubeLut {
  final String name;
  final int size;                // 17 / 33 / 65
  final Float32List rgbTriplets; // 长度 = size^3 * 3

  const CubeLut({
    required this.name,
    required this.size,
    required this.rgbTriplets,
  });

  // ---------------- 解析 ----------------
  static Future<CubeLut> fromFile(String path) async {
    final lines = await File(path).readAsLines();
    int size = 0;
    final values = <double>[];

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.startsWith('LUT_3D_SIZE')) {
        size = int.parse(line.split(RegExp(r'\s+')).last);
        continue;
      }
      // 忽略各种元数据头
      if (line.startsWith('TITLE') ||
          line.startsWith('DOMAIN_') ||
          line.startsWith('LUT_1D_SIZE') ||
          line.startsWith('LUT_1D_INPUT_RANGE') ||
          line.startsWith('LUT_3D_INPUT_RANGE')) {
        continue;
      }

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length == 3) {
        final r = double.tryParse(parts[0]);
        final g = double.tryParse(parts[1]);
        final b = double.tryParse(parts[2]);
        if (r != null && g != null && b != null) {
          values..add(r)..add(g)..add(b);
        }
      }
    }

    if (size == 0) {
      throw const FormatException('LUT_3D_SIZE 未找到');
    }
    final expected = size * size * size * 3;
    if (values.length != expected) {
      throw FormatException(
        '预期 $expected 个值（size=$size），实际 ${values.length}');
    }

    return CubeLut(
      name: path.split(Platform.pathSeparator).last,
      size: size,
      rgbTriplets: Float32List.fromList(values),
    );
  }

  /// 单位 LUT（无修改）—— 用于验证管线正确性
  factory CubeLut.identity({int size = 33}) {
    final values = Float32List(size * size * size * 3);
    int idx = 0;
    for (int b = 0; b < size; b++) {
      for (int g = 0; g < size; g++) {
        for (int r = 0; r < size; r++) {
          values[idx++] = r / (size - 1);
          values[idx++] = g / (size - 1);
          values[idx++] = b / (size - 1);
        }
      }
    }
    return CubeLut(name: 'Identity', size: size, rgbTriplets: values);
  }

  /// 简单LUT（暖调 + 提暗部）
  factory CubeLut.testCinematic({int size = 33}) {
    final values = Float32List(size * size * size * 3);
    int idx = 0;
    for (int b = 0; b < size; b++) {
      for (int g = 0; g < size; g++) {
        for (int r = 0; r < size; r++) {
          double rr = r / (size - 1);
          double gg = g / (size - 1);
          double bb = b / (size - 1);
          // 暖调：抬 R，压 B
          rr = (rr * 1.08).clamp(0.0, 1.0);
          bb = (bb * 0.88).clamp(0.0, 1.0);
          // 抬暗部
          rr = rr < 0.3 ? rr + 0.04 : rr;
          gg = gg < 0.3 ? gg + 0.04 : gg;
          bb = bb < 0.3 ? bb + 0.03 : bb;
          values[idx++] = rr;
          values[idx++] = gg;
          values[idx++] = bb;
        }
      }
    }
    return CubeLut(name: 'Test · Warm Cinematic', size: size, rgbTriplets: values);
  }

  // ---------------- 转 HALD strip 纹理 ----------------
  /// 输出尺寸 (size² × size) 的 RGBA 纹理
  /// .cube 约定：R 变化最快，然后 G，然后 B
  /// 像素布局：(b*N + r, g)
  Future<ui.Image> toHaldStrip() async {
    final w = size * size;
    final h = size;
    final pixels = Uint8List(w * h * 4);

    int src = 0;
    for (int b = 0; b < size; b++) {
      for (int g = 0; g < size; g++) {
        for (int r = 0; r < size; r++) {
          final dstX = b * size + r;
          final dstY = g;
          final dst = (dstY * w + dstX) * 4;
          pixels[dst]     = (rgbTriplets[src]     * 255).clamp(0, 255).round();
          pixels[dst + 1] = (rgbTriplets[src + 1] * 255).clamp(0, 255).round();
          pixels[dst + 2] = (rgbTriplets[src + 2] * 255).clamp(0, 255).round();
          pixels[dst + 3] = 255;
          src += 3;
        }
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }
}