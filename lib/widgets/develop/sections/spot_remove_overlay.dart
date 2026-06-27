import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/crop_params.dart';
import '../../../state/tools/spot_remove_state.dart';
import '../../../utils/path_brush_tracker.dart';

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
  final ui.Image? sourceImage;

  const SpotRemoveOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceImage,
  });

  @override
  ConsumerState<SpotRemoveOverlay> createState() => _SpotRemoveOverlayState();
}

class _SpotRemoveOverlayState extends ConsumerState<SpotRemoveOverlay> {
  Offset? _cursorPos;
  bool _isHovering = false;
  Timer? _exitDebounce;
  PathBrushTracker? _tracker;
  Offset? _paintOffset; // 拖拽时源点相对目标点的固定偏移（PS 仿制图章行为）

  @override
  void dispose() {
    _exitDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotRemoveStateProvider);
    final isSampling = state.samplingButtonOn;

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
            cloneSource: state.cloneSource,
            brushRadius: state.brushRadius,
            imageDisplaySize: widget.imageDisplaySize,
            crop: widget.crop,
            sourceWidth: widget.sourceWidth,
            sourceHeight: widget.sourceHeight,
            cursorPos: _isHovering ? _cursorPos : null,
            isSampling: isSampling,
            paintOffset: _paintOffset,
            isPainting: _tracker != null,
            sourceImage: widget.sourceImage,
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
    final source = state.cloneSource;
    if (source == null) return;
    final target = _screenToSource(pos);
    // 记录源点与目标点的固定偏移，拖拽过程中保持不变
    _paintOffset = Offset(source.dx - target.dx, source.dy - target.dy);
    final tracker = PathBrushTracker(spacing: state.brushRadius * 0.5);
    tracker.start(target);
    _tracker = tracker;
    // 起始点直接放置一个 spot
    ref.read(spotRemoveStateProvider.notifier).addSpot(target);
    setState(() {});
  }

  void _onPanUpdate(Offset pos, SpotRemoveState state) {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker == null || offset == null) return;
    _cursorPos = pos; // 更新光标位置，让 painter 的源点跟随移动
    final notifier = ref.read(spotRemoveStateProvider.notifier);
    for (final t in tracker.move(_screenToSource(pos))) {
      final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
      notifier.addSpotWithSource(s, t);
    }
  }

  void _onPanEnd() {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker != null && offset != null) {
      final notifier = ref.read(spotRemoveStateProvider.notifier);
      for (final t in tracker.end()) {
        final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
        notifier.addSpotWithSource(s, t);
      }
    }
    _tracker = null;
    _paintOffset = null;
    setState(() {});
  }
}

// ═══════════════════════════════════════════════════════════
// 绘制
// ═══════════════════════════════════════════════════════════

class _SpotPainter extends CustomPainter {
  final Offset? cloneSource;
  final double brushRadius;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final Offset? cursorPos;
  final bool isSampling;
  final Offset? paintOffset;
  final bool isPainting;
  final ui.Image? sourceImage;

  _SpotPainter({
    required this.cloneSource,
    required this.brushRadius,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cursorPos,
    required this.isSampling,
    this.paintOffset,
    this.isPainting = false,
    this.sourceImage,
  });

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
    if (cursorPos == null) return;

    final cursorSrc = _screenToSrc(cursorPos!);
    final r = _radiusToScreen(brushRadius, cursorSrc);

    if (isSampling) {
      // 取样模式：白圈 + 十字
      _drawSamplingCursor(canvas, cursorPos!, r);
    } else if (!isPainting && cloneSource != null && sourceImage != null) {
      // 悬停（未按下）：白圈内显示源点区域预览
      _drawPreviewCursor(canvas, cursorPos!, r, cloneSource!);
    } else {
      // 按下绘制 / 无源点：白圈
      _drawTargetCursor(canvas, cursorPos!, r);
    }
  }

  /// 取样光标：白圈 + 十字（PS 风格）
  void _drawSamplingCursor(Canvas canvas, Offset pos, double radius) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pos, radius, p);
    final len = radius * 0.6;
    final gap = radius * 0.15;
    canvas.drawLine(
        Offset(pos.dx - len, pos.dy), Offset(pos.dx - gap, pos.dy), p);
    canvas.drawLine(
        Offset(pos.dx + gap, pos.dy), Offset(pos.dx + len, pos.dy), p);
    canvas.drawLine(
        Offset(pos.dx, pos.dy - len), Offset(pos.dx, pos.dy - gap), p);
    canvas.drawLine(
        Offset(pos.dx, pos.dy + gap), Offset(pos.dx, pos.dy + len), p);
  }

  /// 目标光标：白圈
  void _drawTargetCursor(Canvas canvas, Offset pos, double radius) {
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// 拖拽中：白圈内显示源点区域的圆形预览（PS 仿制图章行为）
  void _drawPreviewCursor(
      Canvas canvas, Offset screenPos, double radius, Offset srcNorm) {
    final img = sourceImage;
    if (img == null) return;

    // 源点在源图像中的像素坐标（clamp 到图像范围）
    final sx = (srcNorm.dx * img.width).clamp(0.0, img.width.toDouble());
    final sy = (srcNorm.dy * img.height).clamp(0.0, img.height.toDouble());
    final pr = (brushRadius * img.width).clamp(1.0, img.width / 2.0);

    // 源区域 clamp 到图像边界
    final srcRect = Rect.fromLTRB(
      (sx - pr).clamp(0.0, img.width.toDouble()),
      (sy - pr).clamp(0.0, img.height.toDouble()),
      (sx + pr).clamp(0.0, img.width.toDouble()),
      (sy + pr).clamp(0.0, img.height.toDouble()),
    );
    // 目标区域（屏幕上的圆圈位置）
    final dstRect = Rect.fromCircle(center: screenPos, radius: radius);

    canvas.save();
    canvas.clipPath(Path()..addOval(dstRect));
    canvas.drawImageRect(img, srcRect, dstRect, Paint());
    canvas.restore();

    // 白色边框
    canvas.drawCircle(
      screenPos,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.cloneSource != cloneSource ||
      old.brushRadius != brushRadius ||
      old.cursorPos != cursorPos ||
      old.isSampling != isSampling ||
      old.isPainting != isPainting ||
      old.paintOffset != paintOffset ||
      old.sourceImage != sourceImage;
}
