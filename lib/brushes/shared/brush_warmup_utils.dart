import 'dart:ui' as ui;

/// Create a 1×1 transparent mask texture for brush shader warmup.
///
/// Used by spot_heal and dodge_burn — their shaders take a mask sampler
/// and a 1×1 empty texture is sufficient to trigger GPU PSO compilation
/// without consuming GPU memory.
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
