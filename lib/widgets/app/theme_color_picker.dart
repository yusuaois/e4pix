import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class ThemeColorWheelDialog extends StatefulWidget {
  final Color initial;
  const ThemeColorWheelDialog({super.key, required this.initial});

  @override
  State<ThemeColorWheelDialog> createState() => _ThemeColorWheelDialogState();
}

class _ThemeColorWheelDialogState extends State<ThemeColorWheelDialog> {
  late HSVColor _hsv; // 光标位置：H,S 自由移动；V 由角度决定
  double _bias = 1.0; // 亮度滑块

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _gray => HSVColor.fromAHSV(
    1,
    0,
    0,
    (_hsv.value * _bias).clamp(0.0, 1.0),
  ).toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.elevatedBg,
      title: Text(tr("colorPickerTitle"), style: AppTypography.headlineSmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: _HueSatWheel(
              hsv: _hsv,
              bias: _bias,
              onChanged: (h, s) {
                // 角度映射为灰阶亮度（0°/360°=暗，180°=亮）
                final t = h / 180.0;
                final v = (t <= 1.0 ? t : 2.0 - t) * 0.86 + 0.07;
                setState(() => _hsv = HSVColor.fromAHSV(1, h, s, v));
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.brightness_6, size: 16, color: AppColors.faintText),
              Expanded(
                child: Slider(
                  value: _bias,
                  onChanged: (v) => setState(() => _bias = v),
                ),
              ),
            ],
          ),
          // 灰度预览条
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: _gray,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.lightBorder),
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
          onPressed: () => Navigator.pop(context, _gray),
          child: Text(tr("confirm")),
        ),
      ],
    );
  }
}

class _HueSatWheel extends StatelessWidget {
  final HSVColor hsv;
  final double bias;
  final void Function(double hue, double sat) onChanged;

  const _HueSatWheel({
    required this.hsv,
    required this.bias,
    required this.onChanged,
  });

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
          child: CustomPaint(size: size, painter: _WheelPainter(hsv, bias)),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  final double bias;

  _WheelPainter(this.hsv, this.bias);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 灰阶色相环
    final hue = SweepGradient(
      colors: const [
        Color(0xFF121212),
        Color(0xFF444444),
        Color(0xFF999999),
        Color(0xFFEEEEEE),
        Color(0xFF999999),
        Color(0xFF444444),
        Color(0xFF121212),
      ],
    ).createShader(rect);
    canvas.drawCircle(center, r, Paint()..shader = hue);

    // 亮度暗角
    if (bias < 1.0) {
      canvas.drawCircle(
        center,
        r,
        Paint()..color = Colors.black.withValues(alpha: 1.0 - bias),
      );
    }

    // 光标：角度跟随 hue，距离跟随 saturation
    final ang = hsv.hue * math.pi / 180;
    final dist = hsv.saturation * r;
    final tp = center + Offset(math.cos(ang) * dist, math.sin(ang) * dist);

    final finalColorValue = (hsv.value * bias).clamp(0.0, 1.0);

    canvas
      ..drawCircle(
        tp,
        9,
        Paint()..color = HSVColor.fromAHSV(1, 0, 0, finalColorValue).toColor(),
      )
      ..drawCircle(
        tp,
        9,
        Paint()
          ..color = AppColors.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv || old.bias != bias;
}
