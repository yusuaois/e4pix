import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'healing_model.dart';
import '../shared/brush_hashes.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/path_brush_tracker.dart';

/// 修复画笔交互覆盖层
///
/// 交互方式与 [SpotRemoveOverlay] 相同：点击或拖拽绘制修复 marks
/// 区别在于 shader 用频域分离混合而非直接像素复制
///
/// 拖拽期间在 Canvas 上绘制硬边预览，松手后提交管线做柔边混合
class HealingOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image? sourceImage;

  /// 为 false 时不处理手势和光标，但仍绘制已提交预览并监听管线完成
  final bool interactive;

  const HealingOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceImage,
    this.interactive = true,
  });

  @override
  ConsumerState<HealingOverlay> createState() => HealingOverlayState();
}

class HealingOverlayState extends ConsumerState<HealingOverlay> {
  // ── 持久化已提交预览（卸载后仍存活）──
  static final List<HealingMark> _persistedMarks = [];
  static int _persistedHash = 0;
  static bool _persistedCommitting = false;

  /// 是否有未渲染 marks 需要保持覆盖层存活
  static bool get hasPendingPreview => _persistedCommitting;
  Offset? _cursorPos;
  bool _isHovering = false;
  Timer? _exitDebounce;
  PathBrushTracker? _tracker;
  Offset? _paintOffset;

  // ── 笔画内本地累积（不触发管线）──
  final List<HealingMark> _strokeMarks = [];

  // ── 已提交但尚未渲染的预览（防闪烁）──
  bool _isCommitting = false;
  final List<HealingMark> _committedPreview = [];
  int _committedMarksHash = 0;

  @override
  void initState() {
    super.initState();
    if (_persistedCommitting && _persistedMarks.isNotEmpty) {
      _committedPreview.addAll(_persistedMarks);
      _committedMarksHash = _persistedHash;
      _isCommitting = true;
      _persistedMarks.clear();
      _persistedHash = 0;
      _persistedCommitting = false;
    }
  }

  @override
  void dispose() {
    if (_isCommitting && _committedPreview.isNotEmpty) {
      _persistedMarks
        ..clear()
        ..addAll(_committedPreview);
      _persistedHash = _committedMarksHash;
      _persistedCommitting = true;
    }
    _exitDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(HealingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactive && !widget.interactive) {
      _paintOffset = null;
      _tracker = null;
      _strokeMarks.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(healingStateProvider);
    final isSampling = state.samplingButtonOn;
    final interactive = widget.interactive;

    ref.listen<Map<String, int>>(renderedBrushHashesProvider, (prev, next) {
      final hash = next['healing'] ?? 0;
      if (_isCommitting && hash == _committedMarksHash) {
        _committedPreview.clear();
        _isCommitting = false;
        if (mounted) setState(() {});
      }
    });

    final painter = CustomPaint(
      size: widget.imageDisplaySize,
      painter: _HealingPainter(
        cloneSource: state.cloneSource,
        brushRadius: state.brushRadius,
        brushHardness: state.brushHardness,
        imageDisplaySize: widget.imageDisplaySize,
        crop: widget.crop,
        sourceWidth: widget.sourceWidth,
        sourceHeight: widget.sourceHeight,
        cursorPos: interactive ? (_isHovering ? _cursorPos : null) : null,
        cursorSrc: interactive
            ? ((_isHovering && _cursorPos != null)
                  ? _screenToSource(_cursorPos!)
                  : null)
            : null,
        isSampling: interactive && isSampling,
        paintOffset: interactive ? _paintOffset : null,
        isPainting: interactive && _tracker != null,
        sourceImage: widget.sourceImage,
        strokeMarks: _strokeMarks,
        committedMarks: _committedPreview,
      ),
    );

    if (!interactive) return IgnorePointer(child: painter);

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
        _exitDebounce = Timer(const Duration(milliseconds: 50), () {
          if (mounted) setState(() => _isHovering = false);
        });
      },
      child: GestureDetector(
        onTapDown: (d) => _onTapDown(d.localPosition, state, isSampling),
        onPanStart: (d) => _onPanStart(d.localPosition, state, isSampling),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, state),
        onPanEnd: (_) => _onPanEnd(),
        onPanCancel: _onPanCancel,
        behavior: HitTestBehavior.translucent,
        child: painter,
      ),
    );
  }

  Offset _screenToSource(Offset screen) => screenToSourceNorm(
    screen: screen,
    imageDisplaySize: widget.imageDisplaySize,
    crop: widget.crop,
    sourceWidth: widget.sourceWidth,
    sourceHeight: widget.sourceHeight,
  );

  void _onTapDown(Offset pos, HealingState state, bool isSampling) {
    if (isSampling) {
      _paintOffset = null;
      ref
          .read(healingStateProvider.notifier)
          .setCloneSource(_screenToSource(pos));
    } else {
      final target = _screenToSource(pos);
      final offset = _paintOffset;
      if (offset != null) {
        ref
            .read(healingStateProvider.notifier)
            .setCloneSource(
              Offset(target.dx + offset.dx, target.dy + offset.dy),
            );
      }
      ref.read(healingStateProvider.notifier).addMark(target);
    }
  }

  void _onPanStart(Offset pos, HealingState state, bool isSampling) {
    if (isSampling) return;
    final target = _screenToSource(pos);
    final Offset source;
    if (_paintOffset != null) {
      source = Offset(
        target.dx + _paintOffset!.dx,
        target.dy + _paintOffset!.dy,
      );
    } else {
      final cs = state.cloneSource;
      if (cs == null) return;
      source = cs;
      _paintOffset = Offset(source.dx - target.dx, source.dy - target.dy);
    }
    final tracker = PathBrushTracker(spacing: state.brushRadius * 0.5);
    tracker.start(target);
    _tracker = tracker;
    _cursorPos = pos;

    _strokeMarks.clear();
    _strokeMarks.add(
      HealingMark(
        source: source,
        target: target,
        radius: state.brushRadius,
        hardness: state.brushHardness,
      ),
    );
    setState(() {});
  }

  void _onPanUpdate(Offset pos, HealingState state) {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker == null || offset == null) return;
    _cursorPos = pos;
    for (final t in tracker.move(_screenToSource(pos))) {
      final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
      _strokeMarks.add(
        HealingMark(
          source: s,
          target: t,
          radius: state.brushRadius,
          hardness: state.brushHardness,
        ),
      );
    }
    setState(() {});
  }

  void _onPanEnd() {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker != null && offset != null) {
      final s = ref.read(healingStateProvider);
      for (final t in tracker.end()) {
        _strokeMarks.add(
          HealingMark(
            source: Offset(t.dx + offset.dx, t.dy + offset.dy),
            target: t,
            radius: s.brushRadius,
            hardness: s.brushHardness,
          ),
        );
      }
    }
    if (offset != null && _cursorPos != null) {
      final cursorSrc = _screenToSource(_cursorPos!);
      ref
          .read(healingStateProvider.notifier)
          .setCloneSource(
            Offset(cursorSrc.dx + offset.dx, cursorSrc.dy + offset.dy),
          );
    }
    if (_strokeMarks.isNotEmpty) {
      ref
          .read(healingStateProvider.notifier)
          .addMarksBatch(List<HealingMark>.from(_strokeMarks));
      _committedMarksHash = hashHealingMarks(
        ref.read(currentParamsNotifierProvider).healingMarks,
      );
      _committedPreview.addAll(_strokeMarks);
      _isCommitting = true;
      _strokeMarks.clear();
    }
    _tracker = null;
    setState(() {});
  }

  void _onPanCancel() {
    _strokeMarks.clear();
    _committedPreview.clear();
    _isCommitting = false;
    _tracker = null;
    setState(() {});
  }
}

// ═══════════════════════════════════════════════════════════
// Painter
// ═══════════════════════════════════════════════════════════

class _HealingPainter extends CustomPainter {
  final Offset? cloneSource;
  final double brushRadius;
  final double brushHardness;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final Offset? cursorPos;
  final Offset? cursorSrc;
  final bool isSampling;
  final Offset? paintOffset;
  final bool isPainting;
  final ui.Image? sourceImage;
  final List<HealingMark> strokeMarks;
  final List<HealingMark> committedMarks;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.low;

  _HealingPainter({
    required this.cloneSource,
    required this.brushRadius,
    required this.brushHardness,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cursorPos,
    required this.cursorSrc,
    required this.isSampling,
    this.paintOffset,
    this.isPainting = false,
    this.sourceImage,
    this.strokeMarks = const [],
    this.committedMarks = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Draw accumulated stroke pixels (hard-edge instant preview) ──
    final img = sourceImage;
    final allPreview = <HealingMark>[...strokeMarks, ...committedMarks];
    if (allPreview.isNotEmpty && img != null) {
      for (final mark in allPreview) {
        _drawStrokeMark(canvas, img, mark);
      }
    }

    if (cursorPos == null || cursorSrc == null) return;

    final r = sourceRadiusToScreen(
      r: brushRadius,
      srcCenter: cursorSrc!,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );

    if (isSampling) {
      _drawSamplingCursor(canvas, cursorPos!, r);
    } else if (!isPainting && cloneSource != null && sourceImage != null) {
      final previewSrc = paintOffset != null
          ? Offset(
              cursorSrc!.dx + paintOffset!.dx,
              cursorSrc!.dy + paintOffset!.dy,
            )
          : cloneSource!;
      _drawPreviewCursor(canvas, cursorPos!, r, previewSrc);
    } else {
      _drawTargetCursor(canvas, cursorPos!, r);
    }

    if (!isSampling && cloneSource != null) {
      final Offset srcScreen;
      if (paintOffset != null) {
        srcScreen = sourceToScreenNorm(
          src: Offset(
            cursorSrc!.dx + paintOffset!.dx,
            cursorSrc!.dy + paintOffset!.dy,
          ),
          imageDisplaySize: imageDisplaySize,
          crop: crop,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
      } else {
        srcScreen = sourceToScreenNorm(
          src: cloneSource!,
          imageDisplaySize: imageDisplaySize,
          crop: crop,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
      }
      _drawSourceCrosshair(canvas, srcScreen);
    }
  }

  void _drawStrokeMark(Canvas canvas, ui.Image img, HealingMark mark) {
    final sxRaw = mark.source.dx * img.width;
    final syRaw = mark.source.dy * img.height;
    final pr = (mark.radius * img.width).clamp(1.0, img.width / 2.0);

    final screenCenter = sourceToScreenNorm(
      src: mark.target,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    final screenR = sourceRadiusToScreen(
      r: mark.radius,
      srcCenter: mark.target,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );

    final rects = computeOOBRects(
      sxRaw: sxRaw,
      syRaw: syRaw,
      pr: pr,
      imageW: img.width.toDouble(),
      imageH: img.height.toDouble(),
      screenCenterX: screenCenter.dx,
      screenCenterY: screenCenter.dy,
      screenR: screenR,
    );
    if (rects == null) return;

    canvas.save();
    canvas.clipPath(Path()..addOval(rects.fullDstRect));
    canvas.drawImageRect(img, rects.srcRect, rects.dstRect, _imagePaint);
    canvas.restore();
  }

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

  void _drawSourceCrosshair(Canvas canvas, Offset pos) {
    const size = 8.0, gap = 2.0;
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

  void _drawPreviewCursor(
    Canvas canvas,
    Offset screenPos,
    double radius,
    Offset srcNorm,
  ) {
    final img = sourceImage;
    if (img == null) return;

    final srxRaw = srcNorm.dx * img.width;
    final sryRaw = srcNorm.dy * img.height;
    final pr = (brushRadius * img.width).clamp(1.0, img.width / 2.0);

    final rects = computeOOBRects(
      sxRaw: srxRaw,
      syRaw: sryRaw,
      pr: pr,
      imageW: img.width.toDouble(),
      imageH: img.height.toDouble(),
      screenCenterX: screenPos.dx,
      screenCenterY: screenPos.dy,
      screenR: radius,
    );
    if (rects == null) {
      _drawTargetCursor(canvas, screenPos, radius);
      return;
    }

    if (brushHardness >= 0.99) {
      canvas.save();
      canvas.clipPath(Path()..addOval(rects.fullDstRect));
      canvas.drawImageRect(img, rects.srcRect, rects.dstRect, _imagePaint);
      canvas.restore();
    } else {
      final t0 = brushHardness.clamp(0.0, 1.0);
      final span = 1.0 - t0;
      double ss(double t) => (3 * t * t - 2 * t * t * t).clamp(0.0, 1.0);
      final gradient = ui.Gradient.radial(
        screenPos,
        radius,
        [
          Colors.white,
          if (span > 0.01) ...{
            Colors.white,
            Colors.white.withValues(alpha: 1.0 - ss(0.25)),
            Colors.white.withValues(alpha: 1.0 - ss(0.5)),
            Colors.white.withValues(alpha: 1.0 - ss(0.75)),
          },
          Colors.transparent,
        ],
        [
          0.0,
          if (span > 0.01) ...{
            t0,
            t0 + span * 0.25,
            t0 + span * 0.5,
            t0 + span * 0.75,
          },
          1.0,
        ],
      );

      canvas.saveLayer(rects.fullDstRect, Paint());
      canvas.drawImageRect(img, rects.srcRect, rects.dstRect, _imagePaint);
      canvas.drawRect(
        rects.fullDstRect,
        Paint()
          ..shader = gradient
          ..blendMode = ui.BlendMode.dstIn,
      );
      canvas.restore();
    }

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
  bool shouldRepaint(_HealingPainter old) =>
      old.cloneSource != cloneSource ||
      old.brushRadius != brushRadius ||
      old.brushHardness != brushHardness ||
      old.cursorPos != cursorPos ||
      old.cursorSrc != cursorSrc ||
      old.isSampling != isSampling ||
      old.isPainting != isPainting ||
      old.paintOffset != paintOffset ||
      old.sourceImage != sourceImage ||
      !listEquals(old.strokeMarks, strokeMarks) ||
      !listEquals(old.committedMarks, committedMarks) ||
      old.imageDisplaySize != imageDisplaySize ||
      old.crop != crop ||
      old.sourceWidth != sourceWidth ||
      old.sourceHeight != sourceHeight;
}
