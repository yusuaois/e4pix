import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 色相-饱和度选色盘对话框
///
/// [isGrayscale] 控制色系：
/// - `false`（默认）：全色域彩虹色相环，选中的是实际 HSV 颜色 水印边框等场景使用
/// - `true`：灰阶色相环，色相角度映射为灰度亮度 主题种子色等场景使用
class ThemeColorWheelDialog extends StatefulWidget {
  final Color initial;
  final bool isGrayscale;

  const ThemeColorWheelDialog({
    super.key,
    required this.initial,
    this.isGrayscale = false,
  });

  @override
  State<ThemeColorWheelDialog> createState() => _ThemeColorWheelDialogState();
}

class _ThemeColorWheelDialogState extends State<ThemeColorWheelDialog> {
  late HSVColor _hsv;
  double _bias = 1.0;

  bool get _gray => widget.isGrayscale;

  @override
  void initState() {
    super.initState();
    final c = HSVColor.fromColor(widget.initial);
    if (widget.isGrayscale) {
      _hsv = c;
    } else {
      // 全色模式：bias 接管亮度控制，hsv.value 固定 1.0
      _bias = c.value.clamp(0.0, 1.0);
      _hsv = HSVColor.fromAHSV(1, c.hue, c.saturation, 1.0);
    }
  }

  /// 当前选中的颜色 — 灰度模式返回灰阶色，全色模式返回 HSV 颜色
  Color get _pickedColor {
    if (_gray) {
      return HSVColor.fromAHSV(
        1,
        0,
        0,
        (_hsv.value * _bias).clamp(0.0, 1.0),
      ).toColor();
    }
    return HSVColor.fromAHSV(
      1,
      _hsv.hue,
      _hsv.saturation,
      (_hsv.value * _bias).clamp(0.0, 1.0),
    ).toColor();
  }

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
              isGrayscale: _gray,
              onChanged: (h, s) {
                if (_gray) {
                  // 灰度模式：角度映射为亮度（0°/360°=暗，180°=亮）
                  final t = h / 180.0;
                  final v = (t <= 1.0 ? t : 2.0 - t) * 0.86 + 0.07;
                  setState(() => _hsv = HSVColor.fromAHSV(1, h, s, v));
                } else {
                  // 全色模式：value 固定 1.0，亮度由 bias 滑块单独控制
                  setState(() => _hsv = HSVColor.fromAHSV(1, h, s, 1.0));
                }
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
          // 颜色预览条
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: _pickedColor,
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
          onPressed: () => Navigator.pop(context, _pickedColor),
          child: Text(tr("confirm")),
        ),
      ],
    );
  }
}

class _HueSatWheel extends StatelessWidget {
  final HSVColor hsv;
  final double bias;
  final bool isGrayscale;
  final void Function(double hue, double sat) onChanged;

  const _HueSatWheel({
    required this.hsv,
    required this.bias,
    required this.isGrayscale,
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
          child: CustomPaint(
            size: size,
            painter: _WheelPainter(hsv, bias, isGrayscale),
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  final double bias;
  final bool isGrayscale;

  _WheelPainter(this.hsv, this.bias, this.isGrayscale);

  static const _grayStops = [
    Color(0xFF121212),
    Color(0xFF444444),
    Color(0xFF999999),
    Color(0xFFEEEEEE),
    Color(0xFF999999),
    Color(0xFF444444),
    Color(0xFF121212),
  ];

  static const _rainbowStops = [
    Color(0xFFFF0000), // red     0°
    Color(0xFFFFFF00), // yellow  60°
    Color(0xFF00FF00), // green   120°
    Color(0xFF00FFFF), // aqua    180°
    Color(0xFF0000FF), // blue    240°
    Color(0xFFFF00FF), // magenta 300°
    Color(0xFFFF0000), // red     360°
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: r);

    // 色相环
    final hue = SweepGradient(
      colors: isGrayscale ? _grayStops : _rainbowStops,
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

    // 光标
    final ang = hsv.hue * math.pi / 180;
    final dist = hsv.saturation * r;
    final tp = center + Offset(math.cos(ang) * dist, math.sin(ang) * dist);

    // 光圈填充色 = 当前选中色（与预览条一致），边框提供与色相环的对比
    final finalValue = (hsv.value * bias).clamp(0.0, 1.0);
    final cursorColor = isGrayscale
        ? HSVColor.fromAHSV(1, 0, 0, finalValue).toColor()
        : HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, finalValue).toColor();

    canvas
      ..drawCircle(tp, 9, Paint()..color = cursorColor)
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
  bool shouldRepaint(_WheelPainter old) =>
      old.hsv != hsv || old.bias != bias || old.isGrayscale != isGrayscale;
}
