import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/crop_params.dart';
import '../../utils/brush_preview_utils.dart';

/// 硬度阈值，≥此值时用 step 替代 smoothstep
const kHardEdgeThreshold = 0.999;

/// 取样光标：白色圆圈 + 十字准星
void drawSamplingCursor(Canvas canvas, Offset pos, double radius) {
  final p = Paint()
    ..color = Colors.white.withValues(alpha: 0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  canvas.drawCircle(pos, radius, p);
  final len = radius * 0.6;
  final gap = radius * 0.15;
  canvas.drawLine(
    Offset(pos.dx - len, pos.dy),
    Offset(pos.dx - gap, pos.dy),
    p,
  );
  canvas.drawLine(
    Offset(pos.dx + gap, pos.dy),
    Offset(pos.dx + len, pos.dy),
    p,
  );
  canvas.drawLine(
    Offset(pos.dx, pos.dy - len),
    Offset(pos.dx, pos.dy - gap),
    p,
  );
  canvas.drawLine(
    Offset(pos.dx, pos.dy + gap),
    Offset(pos.dx, pos.dy + len),
    p,
  );
}

/// 目标光标：白色圆环
void drawTargetCursor(Canvas canvas, Offset pos, double radius) {
  canvas.drawCircle(
    pos,
    radius,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
}

/// 源点十字线指示器
void drawSourceCrosshair(Canvas canvas, Offset pos) {
  const size = 8.0;
  const gap = 2.0;
  final p = Paint()
    ..color = Colors.white.withValues(alpha: 0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  canvas.drawLine(
    Offset(pos.dx - size, pos.dy),
    Offset(pos.dx - gap, pos.dy),
    p,
  );
  canvas.drawLine(
    Offset(pos.dx + gap, pos.dy),
    Offset(pos.dx + size, pos.dy),
    p,
  );
  canvas.drawLine(
    Offset(pos.dx, pos.dy - size),
    Offset(pos.dx, pos.dy - gap),
    p,
  );
  canvas.drawLine(
    Offset(pos.dx, pos.dy + gap),
    Offset(pos.dx, pos.dy + size),
    p,
  );
}

/// 预览光标：在屏幕位置显示克隆源图像预览，OOB 区域裁剪，外圈白色边框
void drawPreviewCursor({
  required Canvas canvas,
  required Offset screenPos,
  required double screenRadius,
  required Offset srcNorm,
  required ui.Image baseImage,
  required double brushRadius,
  required double brushHardness,
  required CropParams crop,
  required int sourceWidth,
  required int sourceHeight,
  required Paint imagePaint,
}) {
  final sxRaw = srcNorm.dx * baseImage.width;
  final syRaw = srcNorm.dy * baseImage.height;
  final pr = (brushRadius * baseImage.width).clamp(1.0, baseImage.width / 2.0);

  canvas.save();
  canvasApplyCrop(canvas, screenPos, crop);

  final rects = computeOOBRects(
    sxRaw: sxRaw,
    syRaw: syRaw,
    pr: pr,
    imageW: baseImage.width.toDouble(),
    imageH: baseImage.height.toDouble(),
    screenCenterX: 0,
    screenCenterY: 0,
    screenR: screenRadius,
  );
  if (rects == null) {
    canvas.restore();
    drawTargetCursor(canvas, screenPos, screenRadius);
    return;
  }

  drawSoftEdgeStamp(
    canvas: canvas,
    image: baseImage,
    rects: rects,
    hardness: brushHardness,
    screenRadius: screenRadius,
    imagePaint: imagePaint,
  );
  canvas.restore();

  canvas.drawCircle(
    screenPos,
    screenRadius,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
}
