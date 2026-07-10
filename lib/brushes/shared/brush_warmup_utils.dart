import 'dart:ui' as ui;

/// 创建 1×1 非空纹理，用于 brush shader 预热
///
/// spot_heal、dodge_burn、sponge 的 shader 在 mask < 0.005 时 early-return，
/// 1×1 R=1.0 纹理迫使 GPU 执行完整计算路径（rgb2hsl/hsl2rgb 等），
/// 确保 PSO 预热覆盖所有代码分支，避免首笔卡顿
Future<ui.Image> createWarmupMask() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  return picture.toImage(1, 1);
}
