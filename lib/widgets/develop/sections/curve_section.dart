import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/rgb_curves.dart';
import '../../../core/models/tone_curve.dart';
import '../../../state/providers.dart';
import 'shared.dart';

class CurveSection extends ConsumerStatefulWidget {
  const CurveSection({super.key});
  @override
  ConsumerState<CurveSection> createState() => _CurveSectionState();
}

class _CurveSectionState extends ConsumerState<CurveSection> {
  int _channel = 0; // 0主 1R 2G 3B
  int? _dragIndex;

  ToneCurve _curveOf(RgbCurves c) => switch (_channel) {
    1 => c.red,
    2 => c.green,
    3 => c.blue,
    4 => c.luminance,
    _ => c.master,
  };

  RgbCurves _withChannel(RgbCurves c, ToneCurve nc) => switch (_channel) {
    1 => c.copyWith(red: nc),
    2 => c.copyWith(green: nc),
    3 => c.copyWith(blue: nc),
    4 => c.copyWith(luminance: nc),
    _ => c.copyWith(master: nc),
  };

  Color _channelColor(BuildContext ctx) => switch (_channel) {
    1 => const Color(0xFFE5534B),
    2 => const Color(0xFF4CAF50),
    3 => const Color(0xFF5B8DEF),
    4 => const Color(0xFFCCCCCC),
    _ => Theme.of(ctx).colorScheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(currentParamsNotifierProvider);
    final curves = params.curves;
    final curve = _curveOf(curves);
    final lineColor = _channelColor(context);

    void commit(ToneCurve next) {
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(curves: _withChannel(curves, next)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Curve'),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _chTab('RGB', 0, Theme.of(context).colorScheme.primary),
              _chTab('R', 1, const Color(0xFFE5534B)),
              _chTab('G', 2, const Color(0xFF4CAF50)),
              _chTab('B', 3, const Color(0xFF5B8DEF)),
              _chTab(tr("lum"), 4, const Color(0xFFCCCCCC)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 155),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    onTapUp: (d) => _onTapUp(d, size, curve, commit),
                    onPanStart: (d) => _onPanStart(d, size, curve),
                    onPanUpdate: (d) => _onPanUpdate(d, size, curve, commit),
                    onPanEnd: (_) => _dragIndex = null,
                    onLongPressStart: (d) =>
                        _onLongPress(d.localPosition, size, curve, commit),
                    child: CustomPaint(
                      painter: _CurvePainter(
                        curve: curve,
                        lineColor: lineColor,
                      ),
                      size: size,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr("curveHint"),
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              TextButton(
                onPressed: curve.isIdentity
                    ? null
                    : () => commit(ToneCurve.identity),
                child: Text(tr("reset"), style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chTab(String label, int ch, Color color) {
    final sel = _channel == ch;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _channel = ch),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: sel ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: sel ? color : Colors.white.withValues(alpha: 0.12),
              width: sel ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 10.5,
              color: sel ? color : Colors.white.withValues(alpha: 0.6),
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Offset2 _toNorm(Offset local, Size size) => Offset2(
    (local.dx / size.width).clamp(0.0, 1.0),
    (1 - local.dy / size.height).clamp(0.0, 1.0),
  );
  Offset _toScreen(Offset2 p, Size size) =>
      Offset(p.x * size.width, (1 - p.y) * size.height);
  int? _hitTest(Offset local, Size size, ToneCurve curve) {
    const r = 22.0;
    for (int i = 0; i < curve.points.length; i++) {
      if ((_toScreen(curve.points[i], size) - local).distance < r) return i;
    }
    return null;
  }

  void _onTapUp(
    TapUpDetails d,
    Size size,
    ToneCurve curve,
    void Function(ToneCurve) commit,
  ) {
    if (_hitTest(d.localPosition, size, curve) != null) return;
    final n = _toNorm(d.localPosition, size);
    final pts = [...curve.points, Offset2(n.x, n.y)]
      ..sort((a, b) => a.x.compareTo(b.x));
    commit(ToneCurve(pts));
  }

  void _onPanStart(DragStartDetails d, Size size, ToneCurve curve) {
    _dragIndex = _hitTest(d.localPosition, size, curve);
  }

  void _onPanUpdate(
    DragUpdateDetails d,
    Size size,
    ToneCurve curve,
    void Function(ToneCurve) commit,
  ) {
    final i = _dragIndex;
    if (i == null) return;
    final n = _toNorm(d.localPosition, size);
    final pts = [...curve.points];
    final isFirst = i == 0, isLast = i == pts.length - 1;
    double nx;
    if (isFirst) {
      nx = 0.0;
    } else if (isLast) {
      nx = 1.0;
    } else {
      nx = n.x.clamp(pts[i - 1].x + 0.01, pts[i + 1].x - 0.01);
    }
    pts[i] = Offset2(nx, n.y);
    commit(ToneCurve(pts));
  }

  void _onLongPress(
    Offset local,
    Size size,
    ToneCurve curve,
    void Function(ToneCurve) commit,
  ) {
    final hit = _hitTest(local, size, curve);
    if (hit == null || hit == 0 || hit == curve.points.length - 1) return;
    final pts = [...curve.points]..removeAt(hit);
    commit(ToneCurve(pts));
  }
}

class _CurvePainter extends CustomPainter {
  final ToneCurve curve;
  final Color lineColor;
  _CurvePainter({required this.curve, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final bg = Paint()..color = const Color(0xFF0E0E12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      bg,
    );

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = w * i / 4;
      final y = h * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    final diag = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(w, 0), diag);

    final lut = curve.toLut(count: 128);
    final path = Path();
    for (int i = 0; i < lut.length; i++) {
      final x = w * i / (lut.length - 1);
      final y = h * (1 - lut[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    for (final p in curve.points) {
      final c = Offset(p.x * w, (1 - p.y) * h);
      canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF0E0E12));
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(c, 2.5, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.curve != curve || old.lineColor != lineColor;
}
