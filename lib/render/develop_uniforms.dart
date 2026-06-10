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
  ui.Image? curveTexture,
}) {
  final p = params;
  final h = p.hsl;
  final g = p.grain;
  int i = 0;

  // 索引 0-1: 分辨率
  shader.setFloat(i++, renderSize.width);
  shader.setFloat(i++, renderSize.height);

  // 索引 2-11: 基础调光调色
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

  // 索引 12-35: HSL 8 波段 × 3 通道
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

  // 索引 36-38: LUT A
  final hasLut = lutTexture != null && lutSize > 0;
  shader.setFloat(i++, hasLut ? params.lutIntensity : 0.0);
  shader.setFloat(i++, lutSize.toDouble());
  shader.setFloat(i++, hasLut ? 1.0 : 0.0);

  // 索引 39-41: LUT B
  final hasLutB = lutTextureB != null && lutSizeB > 0;
  shader.setFloat(i++, hasLutB ? params.lutIntensityB : 0.0);
  shader.setFloat(i++, lutSizeB.toDouble());
  shader.setFloat(i++, hasLutB ? 1.0 : 0.0);

  // 索引 42: 曲线标记
  final hasCurve = curveTexture != null;
  shader.setFloat(i++, hasCurve ? 1.0 : 0.0);

  // 索引 43-54: 颗粒
  shader.setFloat(i++, g.amount / 100.0);
  shader.setFloat(i++, g.size);
  shader.setFloat(i++, g.shadowThreshold / 255.0);
  shader.setFloat(i++, g.highlightThreshold / 255.0);
  shader.setFloat(i++, g.shadowStrength);
  shader.setFloat(i++, g.highlightStrength);
  shader.setFloat(i++, g.shadowSize);
  shader.setFloat(i++, g.highlightSize);
  shader.setFloat(i++, g.redRatio);
  shader.setFloat(i++, g.blueRatio);
  shader.setFloat(i++, g.correlation);
  shader.setFloat(i++, g.colorPreservation);

  assert(i == 55, 'Uniform count mismatch: expected 55, got $i');

  shader.setImageSampler(0, image);
  shader.setImageSampler(1, lutTexture ?? image);
  shader.setImageSampler(2, lutTextureB ?? image);
  shader.setImageSampler(3, curveTexture ?? image);
}
