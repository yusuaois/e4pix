import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/rgb_curves.dart';
import '../../../../core/models/tone_curve.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../state/providers.dart';
import 'curve_section.dart';

/// 竖屏曲线浮层：半透明遮罩 + 居中正方形曲线网格，覆盖在预览区域上方
/// 手势处理逻辑与 [CurveSection] 等价，复用公开的 [CurvePainter]
class CurveOverlay extends ConsumerStatefulWidget {
  const CurveOverlay({super.key});

  @override
  ConsumerState<CurveOverlay> createState() => _CurveOverlayState();
}

class _CurveOverlayState extends ConsumerState<CurveOverlay> {
  int? _dragIndex;

  /// 拖拽节流：避免每次像素移动都触发完整管线重渲染
  Timer? _commitThrottle;
  ToneCurve? _pendingCurve;

  /// 控制点半径，供画布溢出以完整显示边界控制点
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
    _commitThrottle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curves = ref.watch(
      currentParamsNotifierProvider.select((p) => p.curves),
    );
    final curve = _curveOf(curves);
    final baseColor = _channelColor(context);
    // 浮层模式：曲线和控点用半透明主题色
    final lineColor = baseColor.withValues(alpha: 0.55);

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

    return Stack(
      children: [
        // 透明遮罩，拦截手势防止穿透到 InteractiveViewer
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {}, // 吞掉点击遮罩区域的事件，但不做任何事
            child: Container(color: Colors.transparent),
          ),
        ),
        // 曲线网格正方形，靠下对齐，下/左/右 padding 一致
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
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
                },
              ),
            ),
          ),
        ),
      ],
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
