import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'clone_stamp_model.dart';
import '../shared/brush_hashes.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/path_brush_tracker.dart';

/// 图章交互覆盖层
///
/// 点击或拖拽绘制图章 marks，源点通过取样按钮设置
/// 拖拽期间在 Canvas 上绘制硬边预览，松手后提交管线做柔边混合
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
  Offset? _paintOffset; // source→target 固定偏移（PS 图章行为）

  // ── 笔画内本地累积（不触发管线）──
  final List<SpotMark> _strokeSpots = [];

  // ── 已提交但尚未渲染的预览（防闪烁）──
  bool _isCommitting = false;
  final List<SpotMark> _committedPreview = [];
  int _committedSpotsHash = 0;

  @override
  void dispose() {
    _exitDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotRemoveStateProvider);
    final isSampling = state.samplingButtonOn;

    // 管线渲染完已提交的 spots 后清除预览，按 brush id 订阅
    // 哈希匹配避免无关渲染（如滑块拖动）误清除
    ref.listen<Map<String, int>>(renderedBrushHashesProvider, (prev, next) {
      final hash = next['spot_removal'] ?? 0;
      if (_isCommitting && hash == _committedSpotsHash) {
        _committedPreview.clear();
        _isCommitting = false;
        if (mounted) setState(() {});
      }
    });

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
            cursorSrc: (_isHovering && _cursorPos != null)
                ? _screenToSource(_cursorPos!)
                : null,
            isSampling: isSampling,
            paintOffset: _paintOffset,
            isPainting: _tracker != null,
            sourceImage: widget.sourceImage,
            strokeSpots: _strokeSpots,
            committedSpots: _committedPreview,
          ),
        ),
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

  void _onTapDown(Offset pos, SpotRemoveState state, bool isSampling) {
    if (isSampling) {
      _paintOffset = null;
      ref
          .read(spotRemoveStateProvider.notifier)
          .setCloneSource(_screenToSource(pos));
    } else {
      final target = _screenToSource(pos);
      final offset = _paintOffset;
      if (offset != null) {
        ref
            .read(spotRemoveStateProvider.notifier)
            .setCloneSource(
              Offset(target.dx + offset.dx, target.dy + offset.dy),
            );
      }
      ref.read(spotRemoveStateProvider.notifier).addSpot(target);
    }
  }

  void _onPanStart(Offset pos, SpotRemoveState state, bool isSampling) {
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

    _strokeSpots.clear();
    _strokeSpots.add(
      SpotMark(
        source: source,
        target: target,
        radius: state.brushRadius,
        hardness: state.brushHardness,
      ),
    );
    setState(() {});
  }

  void _onPanUpdate(Offset pos, SpotRemoveState state) {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker == null || offset == null) return;
    _cursorPos = pos;
    for (final t in tracker.move(_screenToSource(pos))) {
      final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
      _strokeSpots.add(
        SpotMark(
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
      final s = ref.read(spotRemoveStateProvider);
      for (final t in tracker.end()) {
        _strokeSpots.add(
          SpotMark(
            source: Offset(t.dx + offset.dx, t.dy + offset.dy),
            target: t,
            radius: s.brushRadius,
            hardness: s.brushHardness,
          ),
        );
      }
    }
    // Update clone source (PS behaviour: source follows cursor on release)
    if (offset != null && _cursorPos != null) {
      final cursorSrc = _screenToSource(_cursorPos!);
      ref
          .read(spotRemoveStateProvider.notifier)
          .setCloneSource(
            Offset(cursorSrc.dx + offset.dx, cursorSrc.dy + offset.dy),
          );
    }
    // Batch-commit stroke and keep local preview until pipeline finishes
    if (_strokeSpots.isNotEmpty) {
      ref
          .read(spotRemoveStateProvider.notifier)
          .addSpotsBatch(List<SpotMark>.from(_strokeSpots));
      _committedSpotsHash = hashSpots(
        ref.read(currentParamsNotifierProvider).spots,
      );
      _committedPreview.addAll(_strokeSpots);
      _isCommitting = true;
      _strokeSpots.clear();
    }
    _tracker = null;
    setState(() {});
  }

  void _onPanCancel() {
    _strokeSpots.clear();
    _committedPreview.clear();
    _isCommitting = false;
    _tracker = null;
    setState(() {});
  }
}

// ═══════════════════════════════════════════════════════════
// Painter
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
  final Offset? cursorSrc;
  final bool isSampling;
  final Offset? paintOffset;
  final bool isPainting;
  final ui.Image? sourceImage;
  final List<SpotMark> strokeSpots;
  final List<SpotMark> committedSpots;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.low;

  _SpotPainter({
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
    this.strokeSpots = const [],
    this.committedSpots = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Draw accumulated clone pixels (hard-edge instant preview) ──
    final img = sourceImage;
    final allPreview = <SpotMark>[...strokeSpots, ...committedSpots];
    if (allPreview.isNotEmpty && img != null) {
      for (final spot in allPreview) {
        _drawStrokeSpot(canvas, img, spot);
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

  void _drawStrokeSpot(Canvas canvas, ui.Image img, SpotMark spot) {
    final sxRaw = spot.source.dx * img.width;
    final syRaw = spot.source.dy * img.height;
    final pr = (spot.radius * img.width).clamp(1.0, img.width / 2.0);

    final screenCenter = sourceToScreenNorm(
      src: spot.target,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    final screenR = sourceRadiusToScreen(
      r: spot.radius,
      srcCenter: spot.target,
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
  bool shouldRepaint(_SpotPainter old) =>
      old.cloneSource != cloneSource ||
      old.brushRadius != brushRadius ||
      old.brushHardness != brushHardness ||
      old.cursorPos != cursorPos ||
      old.cursorSrc != cursorSrc ||
      old.isSampling != isSampling ||
      old.isPainting != isPainting ||
      old.paintOffset != paintOffset ||
      old.sourceImage != sourceImage ||
      !listEquals(old.strokeSpots, strokeSpots) ||
      !listEquals(old.committedSpots, committedSpots) ||
      old.imageDisplaySize != imageDisplaySize ||
      old.crop != crop ||
      old.sourceWidth != sourceWidth ||
      old.sourceHeight != sourceHeight;
}
