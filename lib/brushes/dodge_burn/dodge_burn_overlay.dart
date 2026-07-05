import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/path_brush_tracker.dart';
import 'dodge_burn_model.dart';

/// Dodge/Burn overlay — free-form brush like PS Dodge/Burn tools.
///
/// Paint freely to lighten (dodge) or darken (burn) image regions,
/// with tonal range targeting (shadows/midtones/highlights).
class DodgeBurnOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image sourceImage;

  const DodgeBurnOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceImage,
  });

  @override
  ConsumerState<DodgeBurnOverlay> createState() => _DodgeBurnOverlayState();
}

class _DodgeBurnOverlayState extends ConsumerState<DodgeBurnOverlay> {
  Offset? _cursorPos;
  bool _isHovering = false;

  final _tracker = PathBrushTracker(spacing: 0.005);
  final List<Offset> _strokePoints = [];
  bool _isPainting = false;

  double get _brushNorm =>
      ref.read(dodgeBurnStateProvider).brushRadius / 1000.0;
  double get _hardness => ref.read(dodgeBurnStateProvider).brushHardness;

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
      ref
          .read(dodgeBurnStateProvider.notifier)
          .addStrokesBatch(_strokePoints, _brushNorm, _hardness);
    }
    _strokePoints.clear();
    setState(() {});
  }

  void _onPanCancel() {
    _isPainting = false;
    _strokePoints.clear();
    setState(() {});
  }

  void _onTapDown(Offset localPosition) {
    final target = _screenToSourceNorm(localPosition);
    ref
        .read(dodgeBurnStateProvider.notifier)
        .addMarkAt(target, _brushNorm, _hardness);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dodgeBurnStateProvider);
    if (state.brushMode != DodgeBurnBrushMode.active) {
      return const SizedBox.shrink();
    }

    // Cursor color reflects current mode (dodge = warm, burn = cool)
    final cursorColor = state.mode == DodgeBurnMode.dodge
        ? const Color(0x80FFCC00) // warm gold for dodge
        : const Color(0x800088FF); // cool blue for burn

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      onHover: (e) => setState(() {
        _isHovering = true;
        _cursorPos = e.localPosition;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (d) => _onTapDown(d.localPosition),
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: CustomPaint(
          size: widget.imageDisplaySize,
          painter: _DodgeBurnBrushPainter(
            strokePoints: _strokePoints,
            isPainting: _isPainting,
            cursorPos: _cursorPos,
            isHovering: _isHovering,
            brushNorm: _brushNorm,
            cursorColor: cursorColor,
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

class _DodgeBurnBrushPainter extends CustomPainter {
  final List<Offset> strokePoints;
  final bool isPainting;
  final Offset? cursorPos;
  final bool isHovering;
  final double brushNorm;
  final Color cursorColor;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;

  _DodgeBurnBrushPainter({
    required this.strokePoints,
    required this.isPainting,
    this.cursorPos,
    required this.isHovering,
    required this.brushNorm,
    required this.cursorColor,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokePoints.length > 1) {
      final strokePaint = Paint()
        ..color = cursorColor.withAlpha(0x30)
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
      final fillPaint = Paint()
        ..color = cursorColor.withAlpha(0x30)
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

    // Draw cursor as colored outline circle
    if (isHovering && cursorPos != null && !isPainting) {
      final r = brushNorm * imageDisplaySize.width;
      canvas.drawCircle(
        cursorPos!,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = cursorColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DodgeBurnBrushPainter old) {
    return strokePoints != old.strokePoints ||
        isPainting != old.isPainting ||
        cursorPos != old.cursorPos ||
        isHovering != old.isHovering ||
        brushNorm != old.brushNorm ||
        cursorColor != old.cursorColor ||
        imageDisplaySize != old.imageDisplaySize;
  }
}
