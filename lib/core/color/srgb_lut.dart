import 'dart:math' as math;
import 'dart:typed_data';

/// 16-bit linear-light → 8-bit sRGB-encoded 查表。
///
/// LibRaw（在我们的配置下）输出 16-bit linear；Flutter shader 期望的输入是
/// sRGB-encoded 8-bit。这张表是两者之间的桥梁，preview 路径和 export 路径
/// 必须使用同一份转换，否则预览与导出会色彩不一致，AI 配色也会跑偏。
final Uint8List srgbLut16To8 = _build();

Uint8List _build() {
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