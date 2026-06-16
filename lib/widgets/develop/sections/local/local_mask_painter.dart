import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/models/local_adjustment.dart';
import '../../../../core/models/mask_shape.dart';

class MaskPainter extends CustomPainter {
  final List<LocalAdjustment> locals;
  final String? selectedId;
  final Size displaySize;
  final List<Offset>? inProgressPoints;
  final Offset? cursorScreen;
  final double brushRadiusNorm;
  final bool brushErase;
  final bool wandMode;
  final ui.Image? baseViz;
  final bool subjectNegative;
  final Color primaryColor;

  MaskPainter({
    required this.locals,
    required this.selectedId,
    required this.displaySize,
    required this.primaryColor,
    this.inProgressPoints,
    this.cursorScreen,
    this.brushRadiusNorm = 0.08,
    this.brushErase = false,
    this.wandMode = false,
    this.baseViz,
    this.subjectNegative = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in locals) {
      final selected = l.id == selectedId;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.0 : 1.0
        ..color = selected ? primaryColor : AppColors.disabledText;
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = selected ? primaryColor : AppColors.faintText;

      final shape = l.mask;
      if (shape is LinearGradientMask) {
        _paintLinear(canvas, shape, stroke, fill, selected);
      } else if (shape is RadialGradientMask) {
        _paintRadial(canvas, shape, stroke, fill, selected);
      } else if (shape is BrushMask) {
        final ip = selected ? inProgressPoints : null;
        _paintBrush(canvas, shape, selected, ip);
      }
    }
    _paintCursor(canvas, subjectNegative);
  }

  void _paintLinear(
    Canvas canvas,
    LinearGradientMask m,
    Paint stroke,
    Paint fill,
    bool selected,
  ) {
    final s = Offset(
      m.startX * displaySize.width,
      m.startY * displaySize.height,
    );
    final e = Offset(m.endX * displaySize.width, m.endY * displaySize.height);
    canvas.drawLine(s, e, stroke);
    final r = selected ? 7.0 : 5.0;
    canvas.drawCircle(s, r, fill);
    canvas.drawCircle(e, r, fill);
  }

  void _paintRadial(
    Canvas canvas,
    RadialGradientMask m,
    Paint stroke,
    Paint fill,
    bool selected,
  ) {
    final c = Offset(
      m.centerX * displaySize.width,
      m.centerY * displaySize.height,
    );
    final path = Path();
    const N = 64;
    final cs = math.cos(m.rotation);
    final sn = math.sin(m.rotation);
    for (int i = 0; i <= N; i++) {
      final theta = i * 2 * math.pi / N;
      final lx = m.radiusX * math.cos(theta);
      final ly = m.radiusY * math.sin(theta);
      final wx = lx * cs - ly * sn;
      final wy = lx * sn + ly * cs;
      final sx = c.dx + wx * displaySize.width;
      final sy = c.dy + wy * displaySize.height;
      if (i == 0) {
        path.moveTo(sx, sy);
      } else {
        path.lineTo(sx, sy);
      }
    }
    path.close();
    canvas.drawPath(path, stroke);
    final r = selected ? 7.0 : 5.0;
    canvas.drawCircle(c, r, fill);
    if (selected) {
      final right =
          c +
          Offset(
            m.radiusX * displaySize.width * math.cos(m.rotation),
            m.radiusX * displaySize.height * math.sin(m.rotation),
          );
      final bottom =
          c +
          Offset(
            -m.radiusY * displaySize.width * math.sin(m.rotation),
            m.radiusY * displaySize.height * math.cos(m.rotation),
          );
      canvas.drawCircle(right, r, fill);
      canvas.drawCircle(bottom, r, fill);
    }
  }

  void _paintBrush(
    Canvas canvas,
    BrushMask m,
    bool selected,
    List<Offset>? inProgress,
  ) {
    final hasIp = inProgress != null && inProgress.isNotEmpty;
    final hasBase = selected && baseViz != null;
    if (m.strokes.isEmpty && !hasIp && !hasBase) return;
    final tint = primaryColor.withValues(alpha: selected ? 0.22 : 0.10);

    canvas.saveLayer(Offset.zero & displaySize, Paint());
    if (hasBase) {
      canvas.drawImageRect(
        baseViz!,
        Rect.fromLTWH(
          0,
          0,
          baseViz!.width.toDouble(),
          baseViz!.height.toDouble(),
        ),
        Offset.zero & displaySize,
        Paint(),
      );
    }
    for (final s in m.strokes) {
      _overlayStroke(canvas, s.points, s.radius, s.erase, tint);
    }
    if (hasIp) {
      _overlayStroke(canvas, inProgress, brushRadiusNorm, brushErase, tint);
    }
    canvas.restore();
  }

  void _overlayStroke(
    Canvas canvas,
    List<Offset> pts,
    double radiusNorm,
    bool erase,
    Color tint,
  ) {
    if (pts.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = radiusNorm * 2 * displaySize.width;
    if (erase) {
      paint
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xFFFFFFFF);
    } else {
      paint.color = tint;
    }
    if (pts.length == 1) {
      final fill = Paint()..style = PaintingStyle.fill;
      if (erase) {
        fill
          ..blendMode = BlendMode.dstOut
          ..color = const Color(0xFFFFFFFF);
      } else {
        fill.color = tint;
      }
      canvas.drawCircle(
        Offset(pts[0].dx * displaySize.width, pts[0].dy * displaySize.height),
        radiusNorm * displaySize.width,
        fill,
      );
      return;
    }
    final path = Path()
      ..moveTo(pts[0].dx * displaySize.width, pts[0].dy * displaySize.height);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(
        pts[i].dx * displaySize.width,
        pts[i].dy * displaySize.height,
      );
    }
    canvas.drawPath(path, paint);
  }

  void _paintCursor(Canvas canvas, bool negative) {
    final c = cursorScreen;
    if (c == null) return;
    if (wandMode) {
      final p1 = Paint()
        ..color = Colors.black54
        ..strokeWidth = 2.5;
      final p2 = Paint()
        ..color = AppColors.textPrimary
        ..strokeWidth = 1.2;
      const len = 11.0;
      for (final p in [p1, p2]) {
        canvas.drawLine(c + const Offset(-len, 0), c + const Offset(len, 0), p);
        canvas.drawLine(c + const Offset(0, -len), c + const Offset(0, len), p);
      }
      canvas.drawCircle(
        c,
        3,
        Paint()..color = negative ? AppColors.semanticError : primaryColor,
      );
      return;
    }
    final r = brushRadiusNorm * displaySize.width;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.black54,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.textPrimary,
    );
  }

  @override
  bool shouldRepaint(MaskPainter old) =>
      !identical(old.locals, locals) ||
      old.selectedId != selectedId ||
      old.displaySize != displaySize ||
      old.cursorScreen != cursorScreen ||
      old.brushRadiusNorm != brushRadiusNorm ||
      old.brushErase != brushErase ||
      old.wandMode != wandMode ||
      old.baseViz != baseViz ||
      !_listEq(old.inProgressPoints, inProgressPoints);

  static bool _listEq(List<Offset>? a, List<Offset>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.length == b.length;
  }
}
