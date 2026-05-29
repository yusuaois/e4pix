import 'dart:ui' as ui;
import 'dart:ui';
import '../core/models/adjustment_params.dart';

void applyDevelopUniforms({
  required ui.FragmentShader shader,
  required Size renderSize,
  required AdjustmentParams params,
  required ui.Image image,
  ui.Image? lutTexture,
  int lutSize = 0,
  ui.Image? lutTextureB,
  int lutSizeB = 0, 
}) {
  final p = params;
  final h = p.hsl;
  int i = 0;
  shader.setFloat(i++, renderSize.width);
  shader.setFloat(i++, renderSize.height);
  shader.setFloat(i++, p.exposure);
  shader.setFloat(i++, ((p.temperature - 5500) / 4500).clamp(-1.0, 1.0));
  shader.setFloat(i++, p.tint / 100.0);
  shader.setFloat(i++, p.contrast / 100.0);
  shader.setFloat(i++, p.highlights / 100.0);
  shader.setFloat(i++, p.shadows / 100.0);
  shader.setFloat(i++, p.whites / 100.0);
  shader.setFloat(i++, p.blacks / 100.0);
  shader.setFloat(i++, p.saturation / 100.0);
  shader.setFloat(i++, p.vibrance / 100.0);

  for (int k = 0; k < 4; k++) {
    shader.setFloat(i++, h.hues[k] / 100.0);
  }
  for (int k = 4; k < 8; k++) {
    shader.setFloat(i++, h.hues[k] / 100.0);
  }
  for (int k = 0; k < 4; k++) {
    shader.setFloat(i++, h.sats[k] / 100.0);
  }
  for (int k = 4; k < 8; k++) {
    shader.setFloat(i++, h.sats[k] / 100.0);
  }
  for (int k = 0; k < 4; k++) {
    shader.setFloat(i++, h.lums[k] / 100.0);
  }
  for (int k = 4; k < 8; k++) {
    shader.setFloat(i++, h.lums[k] / 100.0);
  }

  final hasLut = lutTexture != null && lutSize > 0;
  shader.setFloat(i++, hasLut ? params.lutIntensity : 0.0);  // 36
  shader.setFloat(i++, lutSize.toDouble());                   // 37
  shader.setFloat(i++, hasLut ? 1.0 : 0.0);                   // 38

  final hasLutB = lutTextureB != null && lutSizeB > 0;
  shader.setFloat(i++, hasLutB ? params.lutIntensityB : 0.0); // 39
  shader.setFloat(i++, lutSizeB.toDouble());                  // 40
  shader.setFloat(i++, hasLutB ? 1.0 : 0.0);                  // 41

  shader.setImageSampler(0, image);
  shader.setImageSampler(1, lutTexture ?? image);
  shader.setImageSampler(2, lutTextureB ?? image);
}
