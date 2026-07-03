import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/path_brush_tracker.dart';

/// Spot Heal overlay — free-form brush like PS Spot Healing Brush.
///
/// Paint freely over defects; strokes are converted to dense overlapping
/// circle marks that the IDW shader fills from surrounding boundary pixels.
class SpotHealOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image sourceImage;

  const SpotHealOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceImage,
  });

  @override
  ConsumerState<SpotHealOverlay> createState() => _SpotHealOverlayState();
}

class _SpotHealOverlayState extends ConsumerState<SpotHealOverlay> {
  Offset? _cursorPos;
  bool _isHovering = false;

  final _tracker = PathBrushTracker(spacing: 0.005); // dense spacing for smooth fill
  final List<Offset> _strokePoints = [];
  bool _isPainting = false;

  double get _brushNorm => ref.read(spotHealStateProvider).brushRadius / 1000.0;
  double get _hardness => ref.read(spotHealStateProvider).brushHardness;

  Offset _screenToSourceNorm(Offset screen) {
    return screenToSourceNorm(
      screen: screen,
      imageDisplaySize: widget.imageDisplaySize,
      crop: widget.crop,
      sourceWidth: widget.sourceWidth,
      sourceHeight: widget.sourceHeight,
    );
  }

  void _onPanStart(DragStartDetails details) {
    _isPainting = true;
    final pos = _screenToSourceNorm(details.localPosition);
    _strokePoints.clear();
    _strokePoints.add(pos);
    _tracker.start(pos);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final pos = _screenToSourceNorm(details.localPosition);
    for (final sampled in _tracker.move(pos)) {
      _strokePoints.add(sampled);
    }
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details) {
    _isPainting = false;
    for (final sampled in _tracker.end()) {
      _strokePoints.add(sampled);
    }
    if (_strokePoints.isNotEmpty) {
      ref.read(spotHealStateProvider.notifier).addStrokesBatch(
            _strokePoints,
            _brushNorm,
            _hardness,
          );
    }
    _strokePoints.clear();
    setState(() {});
  }

  void _onPanCancel() {
    _isPainting = false;
    _strokePoints.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotHealStateProvider);
    if (state.mode != SpotHealMode.active) return const SizedBox.shrink();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      onHover: (e) => setState(() => _cursorPos = e.localPosition),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: CustomPaint(
          size: widget.imageDisplaySize,
          painter: _SpotHealBrushPainter(
            strokePoints: _strokePoints,
            isPainting: _isPainting,
            cursorPos: _cursorPos,
            isHovering: _isHovering,
            brushNorm: _brushNorm,
            imageDisplaySize: widget.imageDisplaySize,
            crop: widget.crop,
            sourceWidth: widget.sourceWidth,
            sourceHeight: widget.sourceHeight,
          ),
        ),
      ),
    );
  }
}

class _SpotHealBrushPainter extends CustomPainter {
  final List<Offset> strokePoints;
  final bool isPainting;
  final Offset? cursorPos;
  final bool isHovering;
  final double brushNorm;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;

  _SpotHealBrushPainter({
    required this.strokePoints,
    required this.isPainting,
    this.cursorPos,
    required this.isHovering,
    required this.brushNorm,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw current stroke as a continuous thick path (same technique as
    // local_mask_painter.dart _overlayStroke) — not individual circles.
    if (strokePoints.length > 1) {
      // Continuous path: round caps + round joins at brush-width thickness
      final strokePaint = Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = brushNorm * 2.0 * imageDisplaySize.width;

      final path = Path();
      final first = sourceToScreenNorm(
        src: strokePoints.first,
        imageDisplaySize: imageDisplaySize,
        crop: crop,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < strokePoints.length; i++) {
        final pt = sourceToScreenNorm(
          src: strokePoints[i],
          imageDisplaySize: imageDisplaySize,
          crop: crop,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, strokePaint);
    } else if (strokePoints.length == 1) {
      // Single point: draw a filled circle
      final fillPaint = Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.fill;
      final c = sourceToScreenNorm(
        src: strokePoints.first,
        imageDisplaySize: imageDisplaySize,
        crop: crop,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      canvas.drawCircle(c, brushNorm * imageDisplaySize.width, fillPaint);
    }

    // Draw cursor as a simple white outline circle
    if (isHovering && cursorPos != null && !isPainting) {
      final r = brushNorm * imageDisplaySize.width;
      canvas.drawCircle(
        cursorPos!, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFFFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotHealBrushPainter old) {
    return strokePoints != old.strokePoints ||
        isPainting != old.isPainting ||
        cursorPos != old.cursorPos ||
        isHovering != old.isHovering ||
        brushNorm != old.brushNorm ||
        imageDisplaySize != old.imageDisplaySize;
  }
}
