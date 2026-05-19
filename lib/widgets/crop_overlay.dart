import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/crop_params.dart';
import '../state/crop_state.dart';
import '../state/interaction_state.dart';

class CropOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;

  const CropOverlay({super.key, required this.imageDisplaySize});

  @override
  ConsumerState<CropOverlay> createState() => _CropOverlayState();
}

enum _Handle { none, body, tl, tr, bl, br, t, b, l, r, rotationKnob }

class _CropOverlayState extends ConsumerState<CropOverlay> {
  _Handle _drag = _Handle.none;
  Offset _dragStart = Offset.zero;
  CropParams _cropAtDragStart = CropParams.identity;

  static const double _handleSize = 14;
  static const double _minSize = 0.05;
  static const double _knobRadius = 14;
  static const double _knobOffset = 36;

  Rect _cropToScreen(CropParams c) {
    final w = widget.imageDisplaySize.width;
    final h = widget.imageDisplaySize.height;
    return Rect.fromLTWH(c.x * w, c.y * h, c.width * w, c.height * h);
  }

  // knob 位置：crop rect 下方 36px 中央；空间不够时放上方
  Offset _knobPosition(Rect screenRect) {
    final dH = widget.imageDisplaySize.height;
    final spaceBelow = dH - screenRect.bottom;
    final cx = (screenRect.left + screenRect.right) / 2;
    return spaceBelow >= 60
        ? Offset(cx, screenRect.bottom + _knobOffset)
        : Offset(cx, screenRect.top - _knobOffset);
  }

  _Handle _hitTest(Offset pos, Rect screenRect) {
    // 优先 knob（在 crop rect 外侧）
    if ((pos - _knobPosition(screenRect)).distance < _knobRadius + 4) {
      return _Handle.rotationKnob;
    }

    bool near(double a, double b) => (a - b).abs() < _handleSize;
    final nearLeft = near(pos.dx, screenRect.left);
    final nearRight = near(pos.dx, screenRect.right);
    final nearTop = near(pos.dy, screenRect.top);
    final nearBottom = near(pos.dy, screenRect.bottom);
    if (nearLeft && nearTop) return _Handle.tl;
    if (nearRight && nearTop) return _Handle.tr;
    if (nearLeft && nearBottom) return _Handle.bl;
    if (nearRight && nearBottom) return _Handle.br;
    if (nearTop && pos.dx > screenRect.left && pos.dx < screenRect.right) {
      return _Handle.t;
    }
    if (nearBottom && pos.dx > screenRect.left && pos.dx < screenRect.right) {
      return _Handle.b;
    }
    if (nearLeft && pos.dy > screenRect.top && pos.dy < screenRect.bottom) {
      return _Handle.l;
    }
    if (nearRight && pos.dy > screenRect.top && pos.dy < screenRect.bottom) {
      return _Handle.r;
    }
    if (screenRect.contains(pos)) return _Handle.body;
    return _Handle.none;
  }

  @override
  Widget build(BuildContext context) {
    final crop = ref.watch(cropDraftProvider);
    final screenRect = _cropToScreen(crop);
    final dW = widget.imageDisplaySize.width;
    final dH = widget.imageDisplaySize.height;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) {
        _drag = _hitTest(d.localPosition, screenRect);
        _dragStart = d.localPosition;
        _cropAtDragStart = crop;
      },
      onPanStart: (_) {
        if (_drag != _Handle.none) {
          ref.read(isUserDraggingSliderProvider.notifier).state = true;
        }
      },
      onPanUpdate: (d) {
        if (_drag == _Handle.none) return;

        // rotation knob 单独处理（角度增量而非位置增量）
        if (_drag == _Handle.rotationKnob) {
          final c0 = _cropAtDragStart;
          final cropCenter = Offset(
            (c0.x + c0.width / 2) * dW,
            (c0.y + c0.height / 2) * dH,
          );
          final startAngle = math.atan2(
            _dragStart.dy - cropCenter.dy,
            _dragStart.dx - cropCenter.dx,
          );
          final currentAngle = math.atan2(
            d.localPosition.dy - cropCenter.dy,
            d.localPosition.dx - cropCenter.dx,
          );
          final deltaDeg = (currentAngle - startAngle) * 180.0 / math.pi;
          final newStraighten = (c0.straighten + deltaDeg).clamp(-45.0, 45.0);
          ref
              .read(cropDraftProvider.notifier)
              .update(c0.copyWith(straighten: newStraighten));
          return;
        }

        final delta = d.localPosition - _dragStart;
        final dx = delta.dx / dW;
        final dy = delta.dy / dH;
        final c0 = _cropAtDragStart;
        var x = c0.x, y = c0.y, w = c0.width, h = c0.height;

        switch (_drag) {
          case _Handle.body:
            x = (c0.x + dx).clamp(0.0, 1.0 - c0.width);
            y = (c0.y + dy).clamp(0.0, 1.0 - c0.height);
            break;
          case _Handle.tl:
            x = (c0.x + dx).clamp(0.0, c0.x + c0.width - _minSize);
            y = (c0.y + dy).clamp(0.0, c0.y + c0.height - _minSize);
            w = c0.x + c0.width - x;
            h = c0.y + c0.height - y;
            break;
          case _Handle.tr:
            y = (c0.y + dy).clamp(0.0, c0.y + c0.height - _minSize);
            w = (c0.width + dx).clamp(_minSize, 1.0 - c0.x);
            h = c0.y + c0.height - y;
            break;
          case _Handle.bl:
            x = (c0.x + dx).clamp(0.0, c0.x + c0.width - _minSize);
            w = c0.x + c0.width - x;
            h = (c0.height + dy).clamp(_minSize, 1.0 - c0.y);
            break;
          case _Handle.br:
            w = (c0.width + dx).clamp(_minSize, 1.0 - c0.x);
            h = (c0.height + dy).clamp(_minSize, 1.0 - c0.y);
            break;
          case _Handle.t:
            y = (c0.y + dy).clamp(0.0, c0.y + c0.height - _minSize);
            h = c0.y + c0.height - y;
            break;
          case _Handle.b:
            h = (c0.height + dy).clamp(_minSize, 1.0 - c0.y);
            break;
          case _Handle.l:
            x = (c0.x + dx).clamp(0.0, c0.x + c0.width - _minSize);
            w = c0.x + c0.width - x;
            break;
          case _Handle.r:
            w = (c0.width + dx).clamp(_minSize, 1.0 - c0.x);
            break;
          case _Handle.none:
          case _Handle.rotationKnob:
            return;
        }

        // 保留 orientation / flip / straighten
        ref
            .read(cropDraftProvider.notifier)
            .update(c0.copyWith(x: x, y: y, width: w, height: h));
      },
      onPanEnd: (_) {
        if (_drag != _Handle.none) {
          ref.read(isUserDraggingSliderProvider.notifier).state = false;
        }
        _drag = _Handle.none;
      },
      onPanCancel: () {
        if (_drag != _Handle.none) {
          ref.read(isUserDraggingSliderProvider.notifier).state = false;
        }
        _drag = _Handle.none;
      },
      child: CustomPaint(
        size: widget.imageDisplaySize,
        painter: _CropPainter(
          crop: crop,
          displaySize: widget.imageDisplaySize,
          knobPosition: _knobPosition(screenRect),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final CropParams crop;
  final Size displaySize;
  final Offset knobPosition;

  _CropPainter({
    required this.crop,
    required this.displaySize,
    required this.knobPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = displaySize.width;
    final h = displaySize.height;
    final r = Rect.fromLTWH(
      crop.x * w,
      crop.y * h,
      crop.width * w,
      crop.height * h,
    );

    // 外部 darken
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, r.top), dark);
    canvas.drawRect(Rect.fromLTWH(0, r.bottom, w, h - r.bottom), dark);
    canvas.drawRect(Rect.fromLTWH(0, r.top, r.left, r.height), dark);
    canvas.drawRect(Rect.fromLTWH(r.right, r.top, w - r.right, r.height), dark);

    // 边框
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, border);

    // 三分线
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 2; i++) {
      final dx = r.left + r.width * i / 3;
      canvas.drawLine(Offset(dx, r.top), Offset(dx, r.bottom), grid);
      final dy = r.top + r.height * i / 3;
      canvas.drawLine(Offset(r.left, dy), Offset(r.right, dy), grid);
    }

    // 8 个 handle
    final handle = Paint()..color = Colors.white;
    void hSquare(Offset c) => canvas.drawRect(
      Rect.fromCenter(center: c, width: 10, height: 10),
      handle,
    );
    hSquare(r.topLeft);
    hSquare(r.topRight);
    hSquare(r.bottomLeft);
    hSquare(r.bottomRight);
    hSquare(Offset(r.center.dx, r.top));
    hSquare(Offset(r.center.dx, r.bottom));
    hSquare(Offset(r.left, r.center.dy));
    hSquare(Offset(r.right, r.center.dy));

    // 旋转 knob
    canvas.drawCircle(
      knobPosition,
      14,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      knobPosition,
      14,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // 指示线（从中心朝上，随 straighten 旋转）
    canvas.save();
    canvas.translate(knobPosition.dx, knobPosition.dy);
    canvas.rotate(crop.straighten * math.pi / 180.0);
    canvas.drawLine(
      Offset.zero,
      const Offset(0, -9),
      Paint()
        ..color = const Color(0xFF6B5BFF)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      const Offset(0, -9),
      2.5,
      Paint()..color = const Color(0xFF6B5BFF),
    );
    canvas.restore();

    // 角度文字
    final tp = TextPainter(
      text: TextSpan(
        text:
            '${crop.straighten >= 0 ? "+" : ""}${crop.straighten.toStringAsFixed(1)}°',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          shadows: [Shadow(blurRadius: 2, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(knobPosition.dx - tp.width / 2, knobPosition.dy + 18),
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.crop != crop || old.knobPosition != knobPosition;
}
