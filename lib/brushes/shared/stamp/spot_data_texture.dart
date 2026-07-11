import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 将 mark 浮点数据编码为 RGBA8 纹理供 shader 采样
///
/// 每个 mark 6 个 float，用 16-bit 定点数编码，两个 float 打包进一个 RGBA8 texel
/// RG 存值 0 的高低字节，BA 存值 1 的高低字节
/// 纹理尺寸 = [maxSpots] × 3 宽 × 1 高，未使用槽位自动填零
Future<ui.Image> encodeMarksToTexture({
  required int count,
  required int maxSpots,
  required List<double> Function(int index) getMarkFloats,
}) async {
  const texelsPerSpot = 3; // 6 值 ÷ 每 texel 2 值
  final width = maxSpots * texelsPerSpot;
  final bytes = Uint8List(width * 4); // 零初始化覆盖未使用槽位

  for (int i = 0; i < count; i++) {
    final floats = getMarkFloats(i);
    assert(floats.length == 6, '每个 mark 必须有 6 个 float');

    for (int j = 0; j < 6; j++) {
      final packed = _packFloat16(floats[j]);
      final high = (packed >> 8) & 0xFF;
      final low = packed & 0xFF;

      final texelIdx = i * texelsPerSpot + (j ~/ 2);
      final offset = texelIdx * 4;
      if (j % 2 == 0) {
        bytes[offset] = high;
        bytes[offset + 1] = low;
      } else {
        bytes[offset + 2] = high;
        bytes[offset + 3] = low;
      }
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes.buffer.asUint8List(),
    width,
    1,
    ui.PixelFormat.rgba8888,
    (image) => completer.complete(image),
  );
  return completer.future;
}

/// 归一化 [0..1] 浮点数 → 16-bit 定点数（0..65535）
int _packFloat16(double value) {
  final clamped = value.clamp(0.0, 1.0);
  return (clamped * 65535.0).round();
}
