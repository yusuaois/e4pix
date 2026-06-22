import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/rgb_curves.dart';
import '../../../core/models/tone_curve.dart';
import '../../../core/theme/app_typography.dart';
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

  /// 拖拽节流：避免每次像素移动都触发完整管线重渲染
  Timer? _commitThrottle;
  ToneCurve? _pendingCurve;

  /// 控制点半径，供画布溢出以完整显示边界控制点
  static const double _pointOverflow = 6.0;

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
    1 => AppColors.curveRed,
    2 => AppColors.curveGreen,
    3 => AppColors.curveBlue,
    4 => AppColors.curveLum,
    _ => Theme.of(ctx).colorScheme.primary,
  };

  @override
  void dispose() {
    _commitThrottle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curves = ref.watch(
      currentParamsNotifierProvider.select((p) => p.curves),
    );
    final curve = _curveOf(curves);
    final lineColor = _channelColor(context);

    void commit(ToneCurve next) {
      final params = ref.read(currentParamsNotifierProvider);
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(curves: _withChannel(curves, next)));
    }

    void commitThrottled(ToneCurve next) {
      _pendingCurve = next;
      if (_commitThrottle != null) return;
      _commitThrottle = Timer(const Duration(milliseconds: 33), () {
        _commitThrottle = null;
        if (!mounted) return;
        final c = _pendingCurve;
        if (c != null) {
          _pendingCurve = null;
          commit(c);
        }
      });
    }

    void flushThrottled() {
      _commitThrottle?.cancel();
      _commitThrottle = null;
      final c = _pendingCurve;
      if (c != null) {
        _pendingCurve = null;
        commit(c);
      }
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
              _chTab('R', 1, AppColors.curveRed),
              _chTab('G', 2, AppColors.curveGreen),
              _chTab('B', 3, AppColors.curveBlue),
              _chTab(tr("lum"), 4, AppColors.curveLum),
            ],
          ),
        ),
        const SizedBox(height: 4),
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
                    onPanUpdate: (d) =>
                        _onPanUpdate(d, size, curve, commitThrottled),
                    onPanEnd: (_) {
                      _dragIndex = null;
                      flushThrottled();
                    },
                    onPanCancel: () {
                      _dragIndex = null;
                      flushThrottled();
                    },
                    onLongPressStart: (d) =>
                        _onLongPress(d.localPosition, size, curve, commit),
                    child: OverflowBox(
                      maxWidth: size.width + 2 * _pointOverflow,
                      maxHeight: size.height + 2 * _pointOverflow,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: size.width + 2 * _pointOverflow,
                        height: size.height + 2 * _pointOverflow,
                        child: CustomPaint(
                          painter: _CurvePainter(
                            curve: curve,
                            lineColor: lineColor,
                            overflow: _pointOverflow,
                          ),
                          size: Size(
                            size.width + 2 * _pointOverflow,
                            size.height + 2 * _pointOverflow,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr("curveHint"),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.disabledText,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: curve.isIdentity
                    ? null
                    : () => commit(ToneCurve.identity),
                child: Text(tr("reset"), style: AppTypography.bodyLarge),
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
              color: sel ? color : AppColors.faintBorder,
              width: sel ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: AppTypography.labelMedium.copyWith(
              color: sel ? color : AppColors.mediumText,
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
  final double overflow;
  _CurvePainter({
    required this.curve,
    required this.lineColor,
    required this.overflow,
  });

  static const double _pointR = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final vw = w - 2 * overflow; // 可视区域宽
    final vh = h - 2 * overflow; // 可视区域高

    // 背景和网格绘制在可视区域
    final bg = Paint()..color = AppColors.scaffoldBg;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset(overflow, overflow) & Size(vw, vh),
        const Radius.circular(6),
      ),
      bg,
    );

    final grid = Paint()
      ..color = AppColors.dividerLine
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = overflow + vw * i / 4;
      final y = overflow + vh * i / 4;
      canvas.drawLine(Offset(x, overflow), Offset(x, overflow + vh), grid);
      canvas.drawLine(Offset(overflow, y), Offset(overflow + vw, y), grid);
    }
    final diag = Paint()
      ..color = AppColors.faintBorder
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(overflow, overflow + vh),
      Offset(overflow + vw, overflow),
      diag,
    );

    // 曲线和 LUT 在可视区域内
    final lut = curve.toLut(count: 128);
    final path = Path();
    for (int i = 0; i < lut.length; i++) {
      final x = overflow + vw * i / (lut.length - 1);
      final y = overflow + vh * (1 - lut[i]);
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

    // 控制点使用 overflow 偏移
    for (final p in curve.points) {
      final c = Offset(overflow + p.x * vw, overflow + (1 - p.y) * vh);
      canvas.drawCircle(c, _pointR, Paint()..color = AppColors.scaffoldBg);
      canvas.drawCircle(
        c,
        _pointR,
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
