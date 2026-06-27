import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/crop_params.dart';
import '../../../core/models/spot_mark.dart';
import '../../../state/params/params_state.dart';
import '../../../state/tools/spot_remove_state.dart';

/// 污点修复交互覆盖层
///
/// PS 风格交互：
/// - 按住取样键（默认 Alt）：白色取样圈 + 十字，点击设置源点
/// - 松开采样键：红色目标圈，点击/拖拽涂抹
/// - 手机用户可通过 Section 中的 "取样" 按钮切换取样模式
class SpotRemoveOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;

  const SpotRemoveOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  ConsumerState<SpotRemoveOverlay> createState() => _SpotRemoveOverlayState();
}

class _SpotRemoveOverlayState extends ConsumerState<SpotRemoveOverlay> {
  Offset? _cursorPos;
  bool _isHovering = false;
  Timer? _exitDebounce;
  Offset? _lastPaintTarget;
  bool _isPainting = false;

  @override
  void dispose() {
    _exitDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotRemoveStateProvider);
    final params = ref.watch(effectiveParamsProvider);
    final spots = params.spots;
    final isSampling =
        ref.watch(samplingHoldProvider) ||
        ref.watch(spotRemoveStateProvider).samplingButtonOn;

    return MouseRegion(
      onEnter: (_) {
        _exitDebounce?.cancel();
        if (!_isHovering) setState(() => _isHovering = true);
      },
      onHover: (e) {
        _exitDebounce?.cancel();
        setState(() {
          _isHovering = true;
          _cursorPos = e.localPosition;
        });
      },
      onExit: (_) {
        // 延迟 50ms，过滤 Riverpod rebuild 引发的假 onExit
        _exitDebounce = Timer(const Duration(milliseconds: 50), () {
          if (mounted) setState(() => _isHovering = false);
        });
      },
      child: GestureDetector(
        onTapDown: (d) => _onTapDown(d.localPosition, state, isSampling),
        onPanStart: (d) => _onPanStart(d.localPosition, state, isSampling),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, state),
        onPanEnd: (_) => _onPanEnd(),
        behavior: HitTestBehavior.translucent,
        child: CustomPaint(
          size: widget.imageDisplaySize,
          painter: _SpotPainter(
            spots: spots,
            cloneSource: state.cloneSource,
            brushRadius: state.brushRadius,
            imageDisplaySize: widget.imageDisplaySize,
            crop: widget.crop,
            sourceWidth: widget.sourceWidth,
            sourceHeight: widget.sourceHeight,
            cursorPos: _isHovering ? _cursorPos : null,
            isSampling: isSampling,
            isPainting: _isPainting,
          ),
        ),
      ),
    );
  }

  Offset _screenToSource(Offset screen) {
    final w = widget.imageDisplaySize.width;
    final h = widget.imageDisplaySize.height;
    final nx = (screen.dx / w).clamp(0.0, 1.0);
    final ny = (screen.dy / h).clamp(0.0, 1.0);
    final (sx, sy) = widget.crop.outputToSourceNorm(
      nx,
      ny,
      widget.sourceWidth,
      widget.sourceHeight,
    );
    return Offset(sx, sy);
  }

  void _onTapDown(Offset pos, SpotRemoveState state, bool isSampling) {
    if (isSampling) {
      ref
          .read(spotRemoveStateProvider.notifier)
          .setCloneSource(_screenToSource(pos));
    } else {
      // addSpot 内部已有 cloneSource == null 保护
      ref.read(spotRemoveStateProvider.notifier).addSpot(_screenToSource(pos));
    }
  }

  void _onPanStart(Offset pos, SpotRemoveState state, bool isSampling) {
    if (isSampling) return;
    _isPainting = true;
    _lastPaintTarget = _screenToSource(pos);
    ref.read(spotRemoveStateProvider.notifier).addSpot(_lastPaintTarget!);
    setState(() {});
  }

  void _onPanUpdate(Offset pos, SpotRemoveState state) {
    if (!_isPainting) return;
    final target = _screenToSource(pos);
    final last = _lastPaintTarget;
    if (last == null) return;
    if ((target - last).distance >= state.brushRadius * 1.5) {
      ref.read(spotRemoveStateProvider.notifier).addSpot(target);
      _lastPaintTarget = target;
    }
  }

  void _onPanEnd() {
    _isPainting = false;
    _lastPaintTarget = null;
    setState(() {});
  }
}

// ═══════════════════════════════════════════════════════════
// 绘制
// ═══════════════════════════════════════════════════════════

class _SpotPainter extends CustomPainter {
  final List<SpotMark> spots;
  final Offset? cloneSource;
  final double brushRadius;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final Offset? cursorPos;
  final bool isSampling;
  final bool isPainting;

  _SpotPainter({
    required this.spots,
    required this.cloneSource,
    required this.brushRadius,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cursorPos,
    required this.isSampling,
    required this.isPainting,
  });

  Offset _srcToScreen(Offset src) {
    final (ox, oy) = crop.forwardToOutputNorm(
      src.dx,
      src.dy,
      sourceWidth,
      sourceHeight,
    );
    return Offset(ox * imageDisplaySize.width, oy * imageDisplaySize.height);
  }

  double _radiusToScreen(double r, Offset center) {
    final (ox0, _) = crop.forwardToOutputNorm(
      center.dx,
      center.dy,
      sourceWidth,
      sourceHeight,
    );
    final (ox1, _) = crop.forwardToOutputNorm(
      center.dx + r,
      center.dy,
      sourceWidth,
      sourceHeight,
    );
    return (ox1 - ox0).abs() * imageDisplaySize.width;
  }

  Offset _screenToSrc(Offset screen) {
    final w = imageDisplaySize.width;
    final h = imageDisplaySize.height;
    final nx = (screen.dx / w).clamp(0.0, 1.0);
    final ny = (screen.dy / h).clamp(0.0, 1.0);
    final (sx, sy) = crop.outputToSourceNorm(nx, ny, sourceWidth, sourceHeight);
    return Offset(sx, sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 已有 spots
    for (final spot in spots) {
      final pos = _srcToScreen(spot.target);
      final r = _radiusToScreen(spot.radius, spot.target);
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.35)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 取样源点标记
    if (cloneSource != null) {
      _drawSourceMarker(
        canvas,
        _srcToScreen(cloneSource!),
        _radiusToScreen(brushRadius, cloneSource!),
      );
    }

    // 光标圆圈
    if (cursorPos != null) {
      final r = _radiusToScreen(brushRadius, _screenToSrc(cursorPos!));
      if (isSampling) {
        _drawSamplingCursor(canvas, cursorPos!, r);
      } else {
        _drawTargetCursor(canvas, cursorPos!, r);
      }
    }
  }

  void _drawSourceMarker(Canvas canvas, Offset pos, double radius) {
    final cl = radius * 0.6, cg = radius * 0.15;
    final p = Paint()
      ..color = Colors.green.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(pos.dx - cl, pos.dy),
      Offset(pos.dx - cg, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx + cg, pos.dy),
      Offset(pos.dx + cl, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy - cl),
      Offset(pos.dx, pos.dy - cg),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + cg),
      Offset(pos.dx, pos.dy + cl),
      p,
    );
    canvas.drawCircle(pos, radius, p);
  }

  void _drawSamplingCursor(Canvas canvas, Offset pos, double radius) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pos, radius, p);
    final cl = radius * 0.6, cg = radius * 0.15;
    canvas.drawLine(
      Offset(pos.dx - cl, pos.dy),
      Offset(pos.dx - cg, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx + cg, pos.dy),
      Offset(pos.dx + cl, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy - cl),
      Offset(pos.dx, pos.dy - cg),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + cg),
      Offset(pos.dx, pos.dy + cl),
      p,
    );
  }

  void _drawTargetCursor(Canvas canvas, Offset pos, double radius) {
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.spots != spots ||
      old.cloneSource != cloneSource ||
      old.brushRadius != brushRadius ||
      old.cursorPos != cursorPos ||
      old.isSampling != isSampling;
}
