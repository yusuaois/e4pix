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
            brushHardness: state.brushHardness,
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
      // 设置新源点时清除旧偏移，下次下笔重新计算
      _paintOffset = null;
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
    // 首次下笔时记录偏移，后续下笔复用同一偏移（PS 仿制图章行为）
    _paintOffset ??= Offset(source.dx - target.dx, source.dy - target.dy);
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
    // 保留 _paintOffset，松手后源点继续跟随光标移动
    setState(() {});
  }
}

// ═══════════════════════════════════════════════════════════
// 绘制
// ═══════════════════════════════════════════════════════════

class _SpotPainter extends CustomPainter {
  final Offset? cloneSource;
  final double brushRadius;
  final double brushHardness;
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
    required this.brushHardness,
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

  /// 归一化源图坐标 → 屏幕坐标
  Offset _srcToScreen(Offset src) {
    final (ox, oy) = crop.forwardToOutputNorm(
      src.dx,
      src.dy,
      sourceWidth,
      sourceHeight,
    );
    return Offset(ox * imageDisplaySize.width, oy * imageDisplaySize.height);
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
      // 有 paintOffset 时源点跟随光标（PS 仿制图章行为），否则用固定 cloneSource
      final previewSrc = paintOffset != null
          ? Offset(
              cursorSrc.dx + paintOffset!.dx,
              cursorSrc.dy + paintOffset!.dy,
            )
          : cloneSource!;
      _drawPreviewCursor(canvas, cursorPos!, r, previewSrc);
    } else {
      // 按下绘制 / 无源点：白圈
      _drawTargetCursor(canvas, cursorPos!, r);
    }

    // 非取样模式下，在源点位置绘制十字标记
    if (!isSampling && cloneSource != null) {
      final Offset srcScreen;
      if (paintOffset != null) {
        // 有偏移时源跟随光标
        srcScreen = _srcToScreen(
          Offset(
            cursorSrc.dx + paintOffset!.dx,
            cursorSrc.dy + paintOffset!.dy,
          ),
        );
      } else {
        // 无偏移时源在固定位置
        srcScreen = _srcToScreen(cloneSource!);
      }
      _drawSourceCrosshair(canvas, srcScreen);
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
      Offset(pos.dx - len, pos.dy),
      Offset(pos.dx - gap, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx + gap, pos.dy),
      Offset(pos.dx + len, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy - len),
      Offset(pos.dx, pos.dy - gap),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + gap),
      Offset(pos.dx, pos.dy + len),
      p,
    );
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

  /// 源点十字标记（非取样模式下显示）
  void _drawSourceCrosshair(Canvas canvas, Offset pos) {
    const size = 8.0;
    const gap = 2.0;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(pos.dx - size, pos.dy),
      Offset(pos.dx - gap, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx + gap, pos.dy),
      Offset(pos.dx + size, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy - size),
      Offset(pos.dx, pos.dy - gap),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + gap),
      Offset(pos.dx, pos.dy + size),
      p,
    );
  }

  /// 悬停预览：白圈内显示源点区域的圆形预览，边缘根据硬度显示柔边渐变
  ///
  /// 图片始终填满整个圆，硬度仅影响边缘透明度：
  /// - 硬度 100%：硬裁剪（与 shader 一致）
  /// - 硬度 < 100%：[saveLayer] + 径向渐变 mask，模拟 shader 的 smoothstep
  void _drawPreviewCursor(
    Canvas canvas,
    Offset screenPos,
    double radius,
    Offset srcNorm,
  ) {
    final img = sourceImage;
    if (img == null) return;

    // 源点在源图像中的像素坐标（clamp 到图像范围）
    final sx = (srcNorm.dx * img.width).clamp(0.0, img.width.toDouble());
    final sy = (srcNorm.dy * img.height).clamp(0.0, img.height.toDouble());
    final pr = (brushRadius * img.width).clamp(1.0, img.width / 2.0);

    final srcRect = Rect.fromLTRB(
      (sx - pr).clamp(0.0, img.width.toDouble()),
      (sy - pr).clamp(0.0, img.height.toDouble()),
      (sx + pr).clamp(0.0, img.width.toDouble()),
      (sy + pr).clamp(0.0, img.height.toDouble()),
    );
    final dstRect = Rect.fromCircle(center: screenPos, radius: radius);

    if (brushHardness >= 0.99) {
      // 硬边：简单裁剪
      canvas.save();
      canvas.clipPath(Path()..addOval(dstRect));
      canvas.drawImageRect(img, srcRect, dstRect, Paint());
      canvas.restore();
    } else {
      // 柔边：渐变 alpha mask，圆圈大小不变，仅边缘透明度渐变
      // 与 shader smoothstep(r * hardness, r, d) 一致
      final innerRadius = radius * brushHardness;
      final gradient = ui.Gradient.radial(
        screenPos,
        radius,
        [
          Colors.white,
          if (innerRadius < radius * 0.99) Colors.white,
          Colors.transparent,
        ],
        [
          0.0,
          if (innerRadius < radius * 0.99)
            (innerRadius / radius).clamp(0.0, 1.0),
          1.0,
        ],
      );

      canvas.saveLayer(dstRect, Paint());
      // 底层：源图
      canvas.drawImageRect(img, srcRect, dstRect, Paint());
      // 上层：渐变 mask（dstIn 用上层 alpha 裁切底层）
      canvas.drawRect(
        dstRect,
        Paint()
          ..shader = gradient
          ..blendMode = ui.BlendMode.dstIn,
      );
      canvas.restore(); // saveLayer
    }

    // 白色边框始终在圆圈边缘
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
      old.brushHardness != brushHardness ||
      old.cursorPos != cursorPos ||
      old.isSampling != isSampling ||
      old.isPainting != isPainting ||
      old.paintOffset != paintOffset ||
      old.sourceImage != sourceImage;
}
