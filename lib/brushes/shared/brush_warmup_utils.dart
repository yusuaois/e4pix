import 'dart:ui' as ui;

/// 创建 1×1 透明纹理，用于 brush shader 预热
///
/// spot_heal 和 dodge_burn 的 shader 接受 mask sampler，
/// 1×1 空纹理足够触发 GPU PSO 编译，且几乎不占 GPU 内存
Future<ui.Image> createEmptyMask() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0x00000000),
  );
  final picture = recorder.endRecording();
  return picture.toImage(1, 1);
}
