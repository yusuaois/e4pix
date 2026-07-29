import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/rgb_curves.dart';
import '../../../../core/models/tone_curve.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../state/providers.dart';
import '../../../../utils/throttler.dart';
import 'curve_gesture_utils.dart';
import 'curve_section.dart';

/// 竖屏曲线浮层：半透明遮罩 + 居中正方形曲线网格，覆盖在预览区域上方
/// 手势处理逻辑与 [CurveSection] 共享 [curve_gesture_utils]
class CurveOverlay extends ConsumerStatefulWidget {
  const CurveOverlay({super.key});

  @override
  ConsumerState<CurveOverlay> createState() => _CurveOverlayState();
}

class _CurveOverlayState extends ConsumerState<CurveOverlay> {
  int? _dragIndex;
  late final _throttle = Throttler<ToneCurve>();

  /// 控制点外溢半径
  static const double _pointOverflow = 6.0;

  int get _channel =>
      (ref.watch(activeOverlayProvider) as CurveActiveOverlay).channel;

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
    _throttle.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curves = ref.watch(
      currentParamsNotifierProvider.select((p) => p.curves),
    );
    final curve = _curveOf(curves);
    final baseColor = _channelColor(context);
    final lineColor = baseColor.withValues(alpha: 0.55);

    void commit(ToneCurve next) {
      final params = ref.read(currentParamsNotifierProvider);
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(curves: _withChannel(curves, next)));
    }

    return Stack(
      children: [
        // 透明遮罩，拦截手势防止穿透到 InteractiveViewer
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(color: Colors.transparent),
          ),
        ),
        _buildCurveGrid(curve, lineColor, commit),
      ],
    );
  }

  Widget _buildCurveGrid(
    ToneCurve curve,
    Color lineColor,
    void Function(ToneCurve) commit,
  ) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return _buildGestureCurve(size, curve, lineColor, commit);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGestureCurve(
    Size size,
    ToneCurve curve,
    Color lineColor,
    void Function(ToneCurve) commit,
  ) {
    return GestureDetector(
      onTapUp: (d) {
        final next = handleTapUp(d.localPosition, size, curve);
        if (next != null) commit(next);
      },
      onPanStart: (d) {
        _dragIndex = hitTest(d.localPosition, size, curve);
      },
      onPanUpdate: (d) {
        final next = handlePanUpdate(d.localPosition, size, curve, _dragIndex);
        if (next != null) _throttle.throttle(next, commit);
      },
      onPanEnd: (_) {
        _dragIndex = null;
        _throttle.flush(commit);
      },
      onPanCancel: () {
        _dragIndex = null;
        _throttle.flush(commit);
      },
      onLongPressStart: (d) {
        final next = handleLongPress(d.localPosition, size, curve);
        if (next != null) commit(next);
      },
      child: OverflowBox(
        maxWidth: size.width + 2 * _pointOverflow,
        maxHeight: size.height + 2 * _pointOverflow,
        alignment: Alignment.center,
        child: SizedBox(
          width: size.width + 2 * _pointOverflow,
          height: size.height + 2 * _pointOverflow,
          child: CustomPaint(
            painter: CurvePainter(
              curve: curve,
              lineColor: lineColor,
              overflow: _pointOverflow,
              drawBackground: false,
            ),
            size: Size(
              size.width + 2 * _pointOverflow,
              size.height + 2 * _pointOverflow,
            ),
          ),
        ),
      ),
    );
  }
}
