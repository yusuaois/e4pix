import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/models/crop_params.dart';
import '../../../utils/brush_preview_utils.dart';

/// 硬度阈值，≥此值时用 step 替代 smoothstep
const kHardEdgeThreshold = 0.999;

/// 取样光标：十字准星 + 采样点
/// 从底到顶：
/// 1. 白色圆环：内径 R/3，外径 R+1
/// 2. 黑色圆圈：半径 R（stroke）
/// 3. 小黑色圆圈：半径 R/3（stroke，与白色圆环内径重合）
/// 4. 黑色十字线
/// 5. 白色小圆点
void drawSamplingUI(Canvas canvas, Offset pos, double radius) {
  const r = 9.0; // 黑色圆圈半径，与 drawSourceCrosshair 一致
  const innerR = r / 3; // 白色圆环内径 / 小黑色圆圈半径
  const outerR = r + 1; // 白色圆环外径
  final ringCenterR = (innerR + outerR) / 2; // 白色圆环绘制半径

  // 1. 白色圆环（最底层）：内径 R/4，外径 R+R/4
  canvas.drawCircle(
    pos,
    ringCenterR,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerR - innerR,
  );

  // 2. 黑色圆圈：半径 R
  canvas.drawCircle(
    pos,
    r,
    Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5,
  );

  // 3. 小黑色圆圈：半径 R/4，位于白色圆环最内层上方
  canvas.drawCircle(
    pos,
    innerR,
    Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5,
  );

  // 4. 黑色十字线
  final crossPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.9)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  canvas.drawLine(
    Offset(pos.dx - r, pos.dy),
    Offset(pos.dx + r, pos.dy),
    crossPaint,
  );
  canvas.drawLine(
    Offset(pos.dx, pos.dy - r),
    Offset(pos.dx, pos.dy + r),
    crossPaint,
  );

  // 5. 白色小圆点（中心）
  canvas.drawCircle(
    pos,
    0.7,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill,
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
  const size = 9.0;
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
