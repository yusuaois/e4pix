import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class ThemeColorWheelDialog extends StatefulWidget {
  final Color initial;
  const ThemeColorWheelDialog({super.key, required this.initial});

  @override
  State<ThemeColorWheelDialog> createState() => _ThemeColorWheelDialogState();
}

class _ThemeColorWheelDialogState extends State<ThemeColorWheelDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A20),
      title: Text(tr("colorPickerTitle"), style: const TextStyle(fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: _HueSatWheel(
              hsv: _hsv,
              onChanged: (h, s) =>
                  setState(() => _hsv = _hsv.withHue(h).withSaturation(s)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.brightness_6, size: 16, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: _hsv.value,
                  onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
                ),
              ),
            ],
          ),
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr("cancel")),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, color),
          child: Text(tr("confirm")),
        ),
      ],
    );
  }
}

class _HueSatWheel extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double hue, double sat) onChanged;
  const _HueSatWheel({required this.hsv, required this.onChanged});

  void _handle(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final vec = local - center;
    final sat = (vec.distance / r).clamp(0.0, 1.0);
    var hue = math.atan2(vec.dy, vec.dx) * 180 / math.pi;
    hue = (hue + 360) % 360;
    onChanged(hue, sat);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          onTapDown: (d) => _handle(d.localPosition, size),
          onPanStart: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          child: CustomPaint(size: size, painter: _WheelPainter(hsv)),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  _WheelPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 色相环
    final hue = SweepGradient(
      colors: const [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    ).createShader(rect);
    canvas.drawCircle(center, r, Paint()..shader = hue);

    final sat = RadialGradient(
      colors: [Colors.white, Colors.white.withValues(alpha: 0)],
    ).createShader(rect);
    canvas.drawCircle(center, r, Paint()..shader = sat);

    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        r,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }

    final ang = hsv.hue * math.pi / 180;
    final dist = hsv.saturation * r;
    final tp = center + Offset(math.cos(ang) * dist, math.sin(ang) * dist);
    canvas
      ..drawCircle(tp, 9, Paint()..color = hsv.toColor())
      ..drawCircle(
        tp,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}
