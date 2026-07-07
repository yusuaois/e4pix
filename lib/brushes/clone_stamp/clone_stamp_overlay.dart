import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'clone_stamp_model.dart';
import '../shared/brush_hashes.dart';
import '../shared/spot_data_texture.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/path_brush_tracker.dart';
import '../../utils/shader_pass_util.dart';

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
  Offset? _paintOffset;

  final List<SpotMark> _strokeSpots = [];

  bool _isCommitting = false;
  final List<SpotMark> _committedPreview = [];
  int _committedSpotsHash = 0;

  ui.Image? _compositedPreview;
  int _compositedCount = 0;
  bool _compositing = false;
  static const _kCompositeBatchSize = 8;

  @override
  void dispose() {
    _exitDebounce?.cancel();
    _compositedPreview?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SpotRemoveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceImage != widget.sourceImage) {
      if (_compositedPreview != null &&
          _compositedPreview != oldWidget.sourceImage) {
        _compositedPreview!.dispose();
      }
      _compositedPreview = null;
      _compositedCount = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotRemoveStateProvider);
    final isSampling = state.samplingButtonOn;

    ref.listen<Map<String, int>>(renderedBrushHashesProvider, (prev, next) {
      final hash = next['spot_removal'] ?? 0;
      if (_isCommitting && hash == _committedSpotsHash) {
        _committedPreview.clear();
        _isCommitting = false;
        if (_compositedPreview != null &&
            _compositedPreview != widget.sourceImage) {
          _compositedPreview!.dispose();
        }
        _compositedPreview = null;
        if (mounted) setState(() {});
      }
    });

    // 完全清空时清理 composited 状态
    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if ((prev?.spots.isNotEmpty ?? false) && next.spots.isEmpty) {
        _committedPreview.clear();
        _isCommitting = false;
        if (_compositedPreview != null &&
            _compositedPreview != widget.sourceImage) {
          _compositedPreview!.dispose();
        }
        _compositedPreview = null;
        _compositedCount = 0;
        _compositing = false;
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
            compositedImage: _compositedPreview,
            compositedCount: _compositedCount,
            strokeSpots: _strokeSpots,
            committedSpots: _committedPreview,
          ),
        ),
      ),
    );
  }

  Future<ui.Image> _runCompositePass({
    required ui.Image base,
    required List<SpotMark> spots,
    required ui.FragmentShader shader,
  }) async {
    final count = spots.length.clamp(0, 128);
    final tex = await encodeMarksToTexture(
      count: count,
      maxSpots: 128,
      getMarkFloats: (i) => [
        spots[i].source.dx,
        spots[i].source.dy,
        spots[i].target.dx,
        spots[i].target.dy,
        spots[i].radius,
        spots[i].hardness,
      ],
    );
    try {
      return await runSingleShaderPass(
        shader: shader,
        outputWidth: base.width,
        outputHeight: base.height,
        samplers: [base, tex],
        setUniforms: (s) {
          s.setFloat(0, base.width.toDouble());
          s.setFloat(1, base.height.toDouble());
          s.setFloat(2, count.toDouble());
          s.setFloat(3, tex.width.toDouble());
        },
      );
    } finally {
      tex.dispose();
    }
  }

  Future<void> _triggerComposite({bool force = false}) async {
    if (_compositing) return;
    final newCount = _strokeSpots.length - _compositedCount;
    if (!force && newCount < _kCompositeBatchSize) return;
    _compositing = true;

    final allNew = _strokeSpots.sublist(_compositedCount);
    final validSpots = allNew.where((s) {
      return !isMarkSourceFullyOOB(
        sourceX: s.source.dx,
        sourceY: s.source.dy,
        radius: s.radius,
        imageWidth: widget.sourceWidth.toDouble(),
        imageHeight: widget.sourceHeight.toDouble(),
      );
    }).toList();

    if (validSpots.isNotEmpty) {
      final prog = ref.read(brushShaderProgramsProvider).value?['spot_removal'];
      final shader = prog?.fragmentShader();
      final base = _compositedPreview ?? widget.sourceImage;
      if (shader != null && base != null) {
        try {
          final result = await _runCompositePass(
            base: base,
            spots: validSpots,
            shader: shader,
          );
          if (!mounted) {
            result.dispose();
            _compositedCount += allNew.length;
            _compositing = false;
            return;
          }
          if (_compositedPreview != null &&
              _compositedPreview != widget.sourceImage) {
            _compositedPreview!.dispose();
          }
          _compositedPreview = result;
          _compositedCount += allNew.length;
        } catch (e) {
          debugPrint('[SpotOverlay] composite failed: $e');
          _compositedPreview?.dispose();
          _compositedPreview = null;
        }
      }
    } else {
      _compositedCount += allNew.length;
    }
    _compositing = false;
    if (mounted) setState(() {});
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
    final tracker = PathBrushTracker(spacing: state.brushRadius * 0.15);
    tracker.start(target);
    _tracker = tracker;
    _cursorPos = pos;

    if (_compositedPreview != null &&
        _compositedPreview != widget.sourceImage) {
      _compositedPreview!.dispose();
    }
    _compositedPreview = null;
    _compositedCount = 0;
    _committedPreview.clear();
    _isCommitting = false;
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
    _triggerComposite();
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
    if (offset != null && _cursorPos != null) {
      final cursorSrc = _screenToSource(_cursorPos!);
      ref
          .read(spotRemoveStateProvider.notifier)
          .setCloneSource(
            Offset(cursorSrc.dx + offset.dx, cursorSrc.dy + offset.dy),
          );
    }
    if (_strokeSpots.isNotEmpty) {
      ref
          .read(spotRemoveStateProvider.notifier)
          .addSpotsBatch(List<SpotMark>.from(_strokeSpots));
      _committedSpotsHash = hashSpots(
        ref.read(currentParamsNotifierProvider).spots,
      );
      _committedPreview
        ..clear()
        ..addAll(_strokeSpots);
      _isCommitting = true;
      _triggerComposite(force: true);
      _strokeSpots.clear();
      _compositedCount = 0;
    }
    _tracker = null;
    setState(() {});
  }

  void _onPanCancel() {
    _strokeSpots.clear();
    _compositedCount = 0;
    _committedPreview.clear();
    _isCommitting = false;
    _compositing = false;
    _tracker = null;
    if (_compositedPreview != null &&
        _compositedPreview != widget.sourceImage) {
      _compositedPreview!.dispose();
    }
    _compositedPreview = null;
    setState(() {});
  }
}

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
  final ui.Image? compositedImage;
  final int compositedCount;
  final List<SpotMark> strokeSpots;
  final List<SpotMark> committedSpots;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.medium;

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
    this.compositedImage,
    this.compositedCount = 0,
    this.strokeSpots = const [],
    this.committedSpots = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasComposited =
        compositedImage != null && compositedImage != sourceImage;
    final srcImg = sourceImage;

    final recorder = ui.PictureRecorder();
    final offscreen = Canvas(recorder);
    bool hasContent = false;

    if (hasComposited && compositedImage != null) {
      offscreen.drawImageRect(
        compositedImage!,
        Rect.fromLTWH(
          0,
          0,
          compositedImage!.width.toDouble(),
          compositedImage!.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, size.width, size.height),
        _imagePaint,
      );
      hasContent = true;

      if (strokeSpots.isNotEmpty) {
        final start = compositedCount.clamp(0, strokeSpots.length);
        for (int i = start; i < strokeSpots.length; i++) {
          _drawStrokeSpot(offscreen, compositedImage!, strokeSpots[i]);
        }
      }
    } else if (srcImg != null) {
      final allPreview = <SpotMark>[...strokeSpots, ...committedSpots];
      for (final spot in allPreview) {
        _drawStrokeSpot(offscreen, srcImg, spot);
      }
      hasContent = true;
    }

    if (hasContent) {
      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
      picture.dispose();
    } else {
      recorder.endRecording().dispose();
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

    // 实时光标预览（目标点圈）始终使用当前最新的 sourceImage
    // 避免 ClearAll 后 composited 残留导致的鬼影
    final cursorBase = sourceImage;

    if (isSampling) {
      _drawSamplingCursor(canvas, cursorPos!, r);
    } else if (!isPainting && cloneSource != null && cursorBase != null) {
      final previewSrc = paintOffset != null
          ? Offset(
              cursorSrc!.dx + paintOffset!.dx,
              cursorSrc!.dy + paintOffset!.dy,
            )
          : cloneSource!;
      _drawPreviewCursor(canvas, cursorPos!, r, previewSrc, cursorBase);
    } else {
      _drawTargetCursor(canvas, cursorPos!, r);
    }

    if (!isSampling && cloneSource != null) {
      final Offset srcScreen = paintOffset != null
          ? sourceToScreenNorm(
              src: Offset(
                cursorSrc!.dx + paintOffset!.dx,
                cursorSrc!.dy + paintOffset!.dy,
              ),
              imageDisplaySize: imageDisplaySize,
              crop: crop,
              sourceWidth: sourceWidth,
              sourceHeight: sourceHeight,
            )
          : sourceToScreenNorm(
              src: cloneSource!,
              imageDisplaySize: imageDisplaySize,
              crop: crop,
              sourceWidth: sourceWidth,
              sourceHeight: sourceHeight,
            );
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

    canvas.save();
    canvasApplyCrop(canvas, screenCenter, crop);

    final rects = computeOOBRects(
      sxRaw: sxRaw,
      syRaw: syRaw,
      pr: pr,
      imageW: img.width.toDouble(),
      imageH: img.height.toDouble(),
      screenCenterX: 0,
      screenCenterY: 0,
      screenR: screenR,
    );
    if (rects == null) {
      canvas.restore();
      return;
    }

    drawSoftEdgeStamp(
      canvas: canvas,
      image: img,
      rects: rects,
      hardness: spot.hardness,
      screenRadius: screenR,
      imagePaint: _imagePaint,
    );
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
    ui.Image baseImage,
  ) {
    final srxRaw = srcNorm.dx * baseImage.width;
    final sryRaw = srcNorm.dy * baseImage.height;
    final pr = (brushRadius * baseImage.width).clamp(
      1.0,
      baseImage.width / 2.0,
    );

    canvas.save();
    canvasApplyCrop(canvas, screenPos, crop);

    final rects = computeOOBRects(
      sxRaw: srxRaw,
      syRaw: sryRaw,
      pr: pr,
      imageW: baseImage.width.toDouble(),
      imageH: baseImage.height.toDouble(),
      screenCenterX: 0,
      screenCenterY: 0,
      screenR: radius,
    );
    if (rects == null) {
      canvas.restore();
      _drawTargetCursor(canvas, screenPos, radius);
      return;
    }

    drawSoftEdgeStamp(
      canvas: canvas,
      image: baseImage,
      rects: rects,
      hardness: brushHardness,
      screenRadius: radius,
      imagePaint: _imagePaint,
    );
    canvas.restore();

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
      old.compositedImage != compositedImage ||
      old.compositedCount != compositedCount ||
      !listEquals(old.strokeSpots, strokeSpots) ||
      !listEquals(old.committedSpots, committedSpots) ||
      old.imageDisplaySize != imageDisplaySize ||
      old.crop != crop ||
      old.sourceWidth != sourceWidth ||
      old.sourceHeight != sourceHeight;
}
