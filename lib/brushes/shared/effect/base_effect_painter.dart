import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/models/crop_params.dart';
import '../../../utils/brush_coord_utils.dart';

/// 效果画笔 Painter 基类：笔画路径 + 单点圆 + 光标环
class BaseEffectPainter extends CustomPainter {
  final List<Offset> strokePoints;
  final bool isPainting;
  final Offset? cursorPos;
  final bool isHovering;
  final double brushNorm;
  final double zoomScale;
  final Color cursorColor;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;

  BaseEffectPainter({
    required this.strokePoints,
    required this.isPainting,
    this.cursorPos,
    required this.isHovering,
    required this.brushNorm,
    this.zoomScale = 1.0,
    required this.cursorColor,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokePoints.length > 1) {
      final strokePaint = Paint()
        ..color = cursorColor.withValues(alpha: 0.188)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = brushNorm * 2.0 * imageDisplaySize.width;

      final path = Path();
      final first = sourceToScreenNorm(
        src: strokePoints.first,
        imageDisplaySize: imageDisplaySize,
        crop: crop,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < strokePoints.length; i++) {
        final pt = sourceToScreenNorm(
          src: strokePoints[i],
          imageDisplaySize: imageDisplaySize,
          crop: crop,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, strokePaint);
    } else if (strokePoints.length == 1) {
      final fillPaint = Paint()
        ..color = cursorColor.withValues(alpha: 0.188)
        ..style = PaintingStyle.fill;
      final c = sourceToScreenNorm(
        src: strokePoints.first,
        imageDisplaySize: imageDisplaySize,
        crop: crop,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      canvas.drawCircle(c, brushNorm * imageDisplaySize.width, fillPaint);
    }

    // 光标环
    if (isHovering && cursorPos != null && !isPainting) {
      final r = brushNorm * imageDisplaySize.width / zoomScale;
      canvas.drawCircle(
        cursorPos!,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / zoomScale
          ..color = cursorColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BaseEffectPainter old) {
    return !listEquals(strokePoints, old.strokePoints) ||
        isPainting != old.isPainting ||
        cursorPos != old.cursorPos ||
        isHovering != old.isHovering ||
        brushNorm != old.brushNorm ||
        zoomScale != old.zoomScale ||
        cursorColor != old.cursorColor ||
        imageDisplaySize != old.imageDisplaySize;
  }
}
