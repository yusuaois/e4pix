import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/local_adjustment.dart';
import '../core/models/mask_shape.dart';
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

  static const double _hitRadius = 14;

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

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(currentParamsNotifierProvider);
    final selectedId = ref.watch(selectedLocalIdProvider);

    if (params.locals.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) {
        final hit = _hitTest(d.localPosition, params.locals, selectedId);
        if (hit == null) {
          _drag = _Handle.none;
          _dragId = null;
          return;
        }
        _dragId = hit.$1;
        _drag = hit.$2;
        _dragStartPos = d.localPosition;
        _shapeAtDragStart =
            params.locals.firstWhere((l) => l.id == _dragId).mask;
        if (selectedId != _dragId) {
          ref.read(selectedLocalIdProvider.notifier).state = _dragId;
        }
      },
      // ⭐ pan 正式开始才标记降级（避免单击 tap 也触发）
      onPanStart: (_) {
        if (_drag != _Handle.none) {
          ref.read(isUserDraggingSliderProvider.notifier).state = true;
        }
      },
      onPanUpdate: (d) {
        if (_drag == _Handle.none || _dragId == null) return;
        _applyDrag(d.localPosition);
      },
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      onTapUp: (d) {
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
        ),
      ),
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
          actions.updateLocal(id, (l) => l.copyWith(
                mask: m.copyWith(
                  startX: newMaskUv.dx.clamp(0.0, 1.0),
                  startY: newMaskUv.dy.clamp(0.0, 1.0),
                ),
              ));
          break;
        case _Handle.linearEnd:
          actions.updateLocal(id, (l) => l.copyWith(
                mask: m.copyWith(
                  endX: newMaskUv.dx.clamp(0.0, 1.0),
                  endY: newMaskUv.dy.clamp(0.0, 1.0),
                ),
              ));
          break;
        case _Handle.linearBody:
          final startUv = _screenToMask(_dragStartPos);
          final dx = newMaskUv.dx - startUv.dx;
          final dy = newMaskUv.dy - startUv.dy;
          actions.updateLocal(id, (l) => l.copyWith(
                mask: m.copyWith(
                  startX: (m.startX + dx).clamp(0.0, 1.0),
                  startY: (m.startY + dy).clamp(0.0, 1.0),
                  endX: (m.endX + dx).clamp(0.0, 1.0),
                  endY: (m.endY + dy).clamp(0.0, 1.0),
                ),
              ));
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
          actions.updateLocal(id, (l) => l.copyWith(
                mask: m.copyWith(
                  centerX: (m.centerX + dx).clamp(0.0, 1.0),
                  centerY: (m.centerY + dy).clamp(0.0, 1.0),
                ),
              ));
          break;
        case _Handle.radialRight:
          final c = _maskToScreen(m.centerX, m.centerY);
          final vec = pos - c;
          final ux = math.cos(m.rotation);
          final uy = math.sin(m.rotation);
          final proj = (vec.dx * ux + vec.dy * uy);
          final newRx = (proj / widget.imageDisplaySize.width).clamp(0.02, 1.0);
          actions.updateLocal(id, (l) =>
              l.copyWith(mask: m.copyWith(radiusX: newRx)));
          break;
        case _Handle.radialBottom:
          final c = _maskToScreen(m.centerX, m.centerY);
          final vec = pos - c;
          final ux = -math.sin(m.rotation);
          final uy = math.cos(m.rotation);
          final proj = (vec.dx * ux + vec.dy * uy);
          final newRy =
              (proj / widget.imageDisplaySize.height).clamp(0.02, 1.0);
          actions.updateLocal(id, (l) =>
              l.copyWith(mask: m.copyWith(radiusY: newRy)));
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

  _MasksPainter({
    required this.locals,
    required this.selectedId,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in locals) {
      final selected = l.id == selectedId;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.0 : 1.0
        ..color = selected
            ? const Color(0xFF6B5BFF)
            : Colors.white.withValues(alpha: 0.45);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = selected
            ? const Color(0xFF6B5BFF)
            : Colors.white.withValues(alpha: 0.5);

      final shape = l.mask;
      if (shape is LinearGradientMask) {
        _paintLinear(canvas, shape, stroke, fill, selected);
      } else if (shape is RadialGradientMask) {
        _paintRadial(canvas, shape, stroke, fill, selected);
      }
    }
  }

  void _paintLinear(Canvas canvas, LinearGradientMask m, Paint stroke,
      Paint fill, bool selected) {
    final s = Offset(
        m.startX * displaySize.width, m.startY * displaySize.height);
    final e =
        Offset(m.endX * displaySize.width, m.endY * displaySize.height);
    canvas.drawLine(s, e, stroke);
    final r = selected ? 7.0 : 5.0;
    canvas.drawCircle(s, r, fill);
    canvas.drawCircle(e, r, fill);
  }

  void _paintRadial(Canvas canvas, RadialGradientMask m, Paint stroke,
      Paint fill, bool selected) {
    final c =
        Offset(m.centerX * displaySize.width, m.centerY * displaySize.height);

    // ⭐ 手动画椭圆：跟 shader / handle 共用同一套数学（归一化空间旋转 → 非等比映射）
    final path = Path();
    const N = 64;
    final cs = math.cos(m.rotation);
    final sn = math.sin(m.rotation);
    for (int i = 0; i <= N; i++) {
      final theta = i * 2 * math.pi / N;
      // 椭圆点在 mask-local 空间（归一化）
      final lx = m.radiusX * math.cos(theta);
      final ly = m.radiusY * math.sin(theta);
      // 旋转到 world 空间（仍为归一化）
      final wx = lx * cs - ly * sn;
      final wy = lx * sn + ly * cs;
      // 非等比映射到屏幕
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

    // 中心 handle
    final r = selected ? 7.0 : 5.0;
    canvas.drawCircle(c, r, fill);
    if (selected) {
      // 右 / 下 handle —— 跟椭圆共用的数学
      final right = c +
          Offset(
            m.radiusX * displaySize.width * math.cos(m.rotation),
            m.radiusX * displaySize.height * math.sin(m.rotation),
          );
      final bottom = c +
          Offset(
            -m.radiusY * displaySize.width * math.sin(m.rotation),
            m.radiusY * displaySize.height * math.cos(m.rotation),
          );
      canvas.drawCircle(right, r, fill);
      canvas.drawCircle(bottom, r, fill);
    }
  }

  @override
  bool shouldRepaint(_MasksPainter old) =>
      !identical(old.locals, locals) ||
      old.selectedId != selectedId ||
      old.displaySize != displaySize;
}