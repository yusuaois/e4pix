import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/local_adjustment.dart';
import '../core/models/mask_shape.dart';
import '../state/brush_state.dart';
import '../state/interaction_state.dart';
import '../state/local_state.dart';
import '../state/params_state.dart';

enum _Handle {
  none,
  linearStart,
  linearEnd,
  linearBody,
  radialCenter,
  radialRight,
  radialBottom,
}

class LocalMaskOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  const LocalMaskOverlay({super.key, required this.imageDisplaySize});

  @override
  ConsumerState<LocalMaskOverlay> createState() => _LocalMaskOverlayState();
}

class _LocalMaskOverlayState extends ConsumerState<LocalMaskOverlay> {
  _Handle _drag = _Handle.none;
  String? _dragId;
  Offset _dragStartPos = Offset.zero;
  MaskShape? _shapeAtDragStart;

  List<Offset>? _paintingPoints;
  Offset? _cursorScreen;
  bool _brushDidMove = false;
  bool _interactionWasBrush = false;

  static const double _hitRadius = 14;

  bool get _brushMode {
    final s = ref.read(selectedLocalProvider);
    return s != null && s.mask is BrushMask;
  }

  Offset _maskToScreen(double mx, double my) => Offset(
    mx * widget.imageDisplaySize.width,
    my * widget.imageDisplaySize.height,
  );

  Offset _screenToMask(Offset s) => Offset(
    s.dx / widget.imageDisplaySize.width,
    s.dy / widget.imageDisplaySize.height,
  );

  Offset _radialEdgeRight(RadialGradientMask m) {
    final c = _maskToScreen(m.centerX, m.centerY);
    final w = widget.imageDisplaySize.width;
    final h = widget.imageDisplaySize.height;
    return c +
        Offset(
          m.radiusX * w * math.cos(m.rotation),
          m.radiusX * h * math.sin(m.rotation),
        );
  }

  Offset _radialEdgeBottom(RadialGradientMask m) {
    final c = _maskToScreen(m.centerX, m.centerY);
    final w = widget.imageDisplaySize.width;
    final h = widget.imageDisplaySize.height;
    return c +
        Offset(
          -m.radiusY * w * math.sin(m.rotation),
          m.radiusY * h * math.cos(m.rotation),
        );
  }

  bool _near(Offset a, Offset b) => (a - b).distance < _hitRadius;

  (String, _Handle)? _hitTest(
    Offset pos,
    List<LocalAdjustment> locals,
    String? selectedId,
  ) {
    final ordered = [
      if (selectedId != null) ...locals.where((l) => l.id == selectedId),
      ...locals.where((l) => l.id != selectedId),
    ];
    for (final local in ordered) {
      final shape = local.mask;
      if (shape is LinearGradientMask) {
        final s = _maskToScreen(shape.startX, shape.startY);
        final e = _maskToScreen(shape.endX, shape.endY);
        if (_near(pos, s)) return (local.id, _Handle.linearStart);
        if (_near(pos, e)) return (local.id, _Handle.linearEnd);
        final dir = e - s;
        final lenSq = dir.dx * dir.dx + dir.dy * dir.dy;
        if (lenSq > 1) {
          final t = ((pos - s).dx * dir.dx + (pos - s).dy * dir.dy) / lenSq;
          if (t > 0 && t < 1) {
            final projected = s + dir * t;
            if ((pos - projected).distance < _hitRadius) {
              return (local.id, _Handle.linearBody);
            }
          }
        }
      } else if (shape is RadialGradientMask) {
        final c = _maskToScreen(shape.centerX, shape.centerY);
        if (_near(pos, c)) return (local.id, _Handle.radialCenter);
        if (_near(pos, _radialEdgeRight(shape))) {
          return (local.id, _Handle.radialRight);
        }
        if (_near(pos, _radialEdgeBottom(shape))) {
          return (local.id, _Handle.radialBottom);
        }
      }
    }
    return null;
  }

  void _endDrag() {
    if (_drag != _Handle.none) {
      ref.read(isUserDraggingSliderProvider.notifier).state = false;
    }
    _drag = _Handle.none;
    _dragId = null;
  }

  void _finishBrush() {
    if (_paintingPoints == null) return;
    final moved = _brushDidMove && _paintingPoints!.length > 1;
    if (moved) {
      _commitBrushStroke();
    } else {
      _paintingPoints = null;
      _cursorScreen = null;
      ref.read(selectedLocalIdProvider.notifier).state = null;
      setState(() {});
    }
  }

  void _commitBrushStroke() {
    final pts = _paintingPoints;
    final id = ref.read(selectedLocalIdProvider);
    if (pts == null || pts.isEmpty || id == null) {
      _paintingPoints = null;
      return;
    }
    final radius = ref.read(brushRadiusProvider);
    final hardness = ref.read(brushHardnessProvider);
    final erase = ref.read(brushEraseProvider);
    final flow = ref.read(brushFlowProvider);
    final auto = ref.read(brushAutoMaskProvider);
    final tol = ref.read(brushToleranceProvider);
    final edge = ref.read(brushEdgeStrengthProvider);
    LocalAdjustmentActions(ref).addStrokeTo(
      id,
      BrushStroke(
        points: List.of(pts),
        radius: radius,
        hardness: hardness,
        erase: erase,
        flow: flow,
        autoMask: auto,
        tolerance: tol,
        edgeStrength: edge,
      ),
    );
    _paintingPoints = null;
    _cursorScreen = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(currentParamsNotifierProvider);
    final selectedId = ref.watch(selectedLocalIdProvider);
    final selected = ref.watch(selectedLocalProvider);
    final isBrush = selected != null && selected.mask is BrushMask;
    final brushRadius = ref.watch(brushRadiusProvider);
    final brushErase = ref.watch(brushEraseProvider);

    if (params.locals.isEmpty) return const SizedBox.shrink();

    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) {
        _interactionWasBrush = _brushMode;
        if (_interactionWasBrush) {
          _cursorScreen = d.localPosition;
          _paintingPoints = [_screenToMask(d.localPosition)];
          _brushDidMove = false;
          setState(() {});
          return;
        }
        final hit = _hitTest(d.localPosition, params.locals, selectedId);
        if (hit == null) {
          _drag = _Handle.none;
          _dragId = null;
          return;
        }
        _dragId = hit.$1;
        _drag = hit.$2;
        _dragStartPos = d.localPosition;
        _shapeAtDragStart = params.locals
            .firstWhere((l) => l.id == _dragId)
            .mask;
        if (selectedId != _dragId) {
          ref.read(selectedLocalIdProvider.notifier).state = _dragId;
        }
      },
      onPanStart: (_) {
        if (_interactionWasBrush) return;
        if (_drag != _Handle.none) {
          ref.read(isUserDraggingSliderProvider.notifier).state = true;
        }
      },
      onPanUpdate: (d) {
        if (_interactionWasBrush) {
          if (_paintingPoints == null) return;
          _brushDidMove = true;
          _cursorScreen = d.localPosition;
          _paintingPoints!.add(_screenToMask(d.localPosition));
          setState(() {});
          return;
        }
        if (_drag == _Handle.none || _dragId == null) return;
        _applyDrag(d.localPosition);
      },
      onPanEnd: (_) {
        if (_interactionWasBrush) {
          _finishBrush();
          return;
        }
        _endDrag();
      },
      onPanCancel: () {
        if (_interactionWasBrush) {
          _finishBrush();
          return;
        }
        _endDrag();
      },
      onTapUp: (d) {
        if (_interactionWasBrush) {
          _finishBrush();
          return;
        }
        final hit = _hitTest(d.localPosition, params.locals, selectedId);
        if (hit == null) {
          ref.read(selectedLocalIdProvider.notifier).state = null;
        } else if (hit.$1 != selectedId) {
          ref.read(selectedLocalIdProvider.notifier).state = hit.$1;
        }
      },
      child: CustomPaint(
        size: widget.imageDisplaySize,
        painter: _MasksPainter(
          locals: params.locals,
          selectedId: selectedId,
          displaySize: widget.imageDisplaySize,
          inProgressPoints: _paintingPoints == null
              ? null
              : List.of(_paintingPoints!),
          cursorScreen: isBrush ? _cursorScreen : null,
          brushRadiusNorm: brushRadius,
          brushErase: brushErase,
        ),
      ),
    );

    if (!isBrush) return gesture;

    return MouseRegion(
      onHover: (e) => setState(() => _cursorScreen = e.localPosition),
      onExit: (_) {
        if (_paintingPoints == null) setState(() => _cursorScreen = null);
      },
      child: gesture,
    );
  }

  void _applyDrag(Offset pos) {
    final id = _dragId;
    if (id == null || _shapeAtDragStart == null) return;
    final shape0 = _shapeAtDragStart!;
    final actions = LocalAdjustmentActions(ref);
    final newMaskUv = _screenToMask(pos);

    if (shape0 is LinearGradientMask) {
      final m = shape0;
      switch (_drag) {
        case _Handle.linearStart:
          actions.updateLocal(
            id,
            (l) => l.copyWith(
              mask: m.copyWith(
                startX: newMaskUv.dx.clamp(0.0, 1.0),
                startY: newMaskUv.dy.clamp(0.0, 1.0),
              ),
            ),
          );
          break;
        case _Handle.linearEnd:
          actions.updateLocal(
            id,
            (l) => l.copyWith(
              mask: m.copyWith(
                endX: newMaskUv.dx.clamp(0.0, 1.0),
                endY: newMaskUv.dy.clamp(0.0, 1.0),
              ),
            ),
          );
          break;
        case _Handle.linearBody:
          final startUv = _screenToMask(_dragStartPos);
          final dx = newMaskUv.dx - startUv.dx;
          final dy = newMaskUv.dy - startUv.dy;
          actions.updateLocal(
            id,
            (l) => l.copyWith(
              mask: m.copyWith(
                startX: (m.startX + dx).clamp(0.0, 1.0),
                startY: (m.startY + dy).clamp(0.0, 1.0),
                endX: (m.endX + dx).clamp(0.0, 1.0),
                endY: (m.endY + dy).clamp(0.0, 1.0),
              ),
            ),
          );
          break;
        default:
          break;
      }
    } else if (shape0 is RadialGradientMask) {
      final m = shape0;
      switch (_drag) {
        case _Handle.radialCenter:
          final startUv = _screenToMask(_dragStartPos);
          final dx = newMaskUv.dx - startUv.dx;
          final dy = newMaskUv.dy - startUv.dy;
          actions.updateLocal(
            id,
            (l) => l.copyWith(
              mask: m.copyWith(
                centerX: (m.centerX + dx).clamp(0.0, 1.0),
                centerY: (m.centerY + dy).clamp(0.0, 1.0),
              ),
            ),
          );
          break;
        case _Handle.radialRight:
          final c = _maskToScreen(m.centerX, m.centerY);
          final vec = pos - c;
          final ux = math.cos(m.rotation);
          final uy = math.sin(m.rotation);
          final proj = (vec.dx * ux + vec.dy * uy);
          final newRx = (proj / widget.imageDisplaySize.width).clamp(0.02, 1.0);
          actions.updateLocal(
            id,
            (l) => l.copyWith(mask: m.copyWith(radiusX: newRx)),
          );
          break;
        case _Handle.radialBottom:
          final c = _maskToScreen(m.centerX, m.centerY);
          final vec = pos - c;
          final ux = -math.sin(m.rotation);
          final uy = math.cos(m.rotation);
          final proj = (vec.dx * ux + vec.dy * uy);
          final newRy = (proj / widget.imageDisplaySize.height).clamp(
            0.02,
            1.0,
          );
          actions.updateLocal(
            id,
            (l) => l.copyWith(mask: m.copyWith(radiusY: newRy)),
          );
          break;
        default:
          break;
      }
    }
  }
}

class _MasksPainter extends CustomPainter {
  final List<LocalAdjustment> locals;
  final String? selectedId;
  final Size displaySize;
  final List<Offset>? inProgressPoints;
  final Offset? cursorScreen;
  final double brushRadiusNorm;
  final bool brushErase;

  _MasksPainter({
    required this.locals,
    required this.selectedId,
    required this.displaySize,
    this.inProgressPoints,
    this.cursorScreen,
    this.brushRadiusNorm = 0.08,
    this.brushErase = false,
  });

  static const _purple = Color(0xFF6B5BFF);

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in locals) {
      final selected = l.id == selectedId;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.0 : 1.0
        ..color = selected ? _purple : Colors.white.withValues(alpha: 0.45);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = selected ? _purple : Colors.white.withValues(alpha: 0.5);

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
    _paintCursor(canvas);
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
    if (m.strokes.isEmpty && !hasIp) return;
    final tint = _purple.withValues(alpha: selected ? 0.22 : 0.10);

    canvas.saveLayer(Offset.zero & displaySize, Paint());
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

  void _paintCursor(Canvas canvas) {
    final c = cursorScreen;
    if (c == null) return;
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
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MasksPainter old) =>
      !identical(old.locals, locals) ||
      old.selectedId != selectedId ||
      old.displaySize != displaySize ||
      old.cursorScreen != cursorScreen ||
      old.brushRadiusNorm != brushRadiusNorm ||
      old.brushErase != brushErase ||
      !_listEq(old.inProgressPoints, inProgressPoints);

  static bool _listEq(List<Offset>? a, List<Offset>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.length == b.length;
  }
}
