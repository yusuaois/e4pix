import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'healing_model.dart';
import '../shared/brush_hashes.dart';
import '../shared/spot_data_texture.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/path_brush_tracker.dart';
import '../../utils/shader_pass_util.dart';

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
  // 持久化已提交预览（卸载后仍存活）
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

  // 笔画内本地累积（不触发管线）
  final List<HealingMark> _strokeMarks = [];

  // 已提交但尚未渲染的预览（防闪烁）
  bool _isCommitting = false;
  final List<HealingMark> _committedPreview = [];
  int _committedMarksHash = 0;

  // GPU 增量合成预览
  ui.Image? _compositedPreview;
  int _compositedCount = 0; // 已合成 mark 数，_strokeMarks 此前的已处理
  bool _compositing = false;
  static const _kCompositeBatchSize = 8;

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
    _compositedPreview?.dispose();
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
    // sourceImage 更新（如清空斑点导致 developOutput 刷新）→ 重置累积合成
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
    final state = ref.watch(healingStateProvider);
    final isSampling = state.samplingButtonOn;
    final interactive = widget.interactive;

    ref.listen<Map<String, int>>(renderedBrushHashesProvider, (prev, next) {
      final hash = next['healing'] ?? 0;
      if (_isCommitting && hash == _committedMarksHash) {
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

    // 外部清空 marks 时立即清理 committed preview + composited
    // 完全清空时清理 composited 状态
    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if ((prev?.healingMarks.isNotEmpty ?? false) &&
          next.healingMarks.isEmpty) {
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
        compositedImage: _compositedPreview,
        compositedCount: _compositedCount,
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

  /// 用修复 shader 将 [marks] 合成到 [base] 上，返回新纹理
  Future<ui.Image> _runCompositePass({
    required ui.Image base,
    required List<HealingMark> marks,
    required ui.FragmentShader shader,
  }) async {
    final count = marks.length.clamp(0, 128);
    final tex = await encodeMarksToTexture(
      count: count,
      maxSpots: 128,
      getMarkFloats: (i) => [
        marks[i].source.dx,
        marks[i].source.dy,
        marks[i].target.dx,
        marks[i].target.dy,
        marks[i].radius,
        marks[i].hardness,
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

  /// 异步触发增量合成，带并发守卫
  Future<void> _triggerComposite({bool force = false}) async {
    if (_compositing) return;
    final newCount = _strokeMarks.length - _compositedCount;
    if (!force && newCount < _kCompositeBatchSize) return;
    _compositing = true;

    final allNew = _strokeMarks.sublist(_compositedCount);
    final validMarks = allNew.where((m) {
      return !isMarkSourceFullyOOB(
        sourceX: m.source.dx,
        sourceY: m.source.dy,
        radius: m.radius,
        imageWidth: widget.sourceWidth.toDouble(),
        imageHeight: widget.sourceHeight.toDouble(),
      );
    }).toList();

    if (validMarks.isNotEmpty) {
      final prog = ref.read(brushShaderProgramsProvider).value?['healing'];
      final shader = prog?.fragmentShader();
      final base = _compositedPreview ?? widget.sourceImage;
      if (shader != null && base != null) {
        try {
          final result = await _runCompositePass(
            base: base,
            marks: validMarks,
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
          debugPrint('[HealingOverlay] composite failed: $e');
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
    final tracker = PathBrushTracker(spacing: state.brushRadius * 0.15);
    tracker.start(target);
    _tracker = tracker;
    _cursorPos = pos;

    // 新笔画开始：清理上次 GPU 合成预览
    if (_compositedPreview != null &&
        _compositedPreview != widget.sourceImage) {
      _compositedPreview!.dispose();
    }
    _compositedPreview = null;
    _compositedCount = 0;
    _committedPreview.clear();
    _isCommitting = false;
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
    _triggerComposite();
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
      _committedPreview
        ..clear()
        ..addAll(_strokeMarks);
      _isCommitting = true;
      _triggerComposite(force: true); // 强制最终合成，确保所有 mark 都进 compositedPreview
      _strokeMarks.clear();
      _compositedCount = 0;
    }
    _tracker = null;
    setState(() {});
  }

  void _onPanCancel() {
    _strokeMarks.clear();
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
  final ui.Image? compositedImage;
  final int compositedCount;
  final List<HealingMark> strokeMarks;
  final List<HealingMark> committedMarks;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.medium;

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
    this.compositedImage,
    this.compositedCount = 0,
    this.strokeMarks = const [],
    this.committedMarks = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasComposited =
        compositedImage != null && compositedImage != sourceImage;
    final srcImg = sourceImage;

    // 离屏绘制临时 marks
    final recorder = ui.PictureRecorder();
    final offscreen = Canvas(recorder);
    bool hasContent = false;

    if (hasComposited && compositedImage != null) {
      // 基底层：shader 权威结果（零误差，包含所有已烘焙 marks）
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

      // 仅绘制未烘焙尾部（从 composited 采样，看到跨 batch 修改）
      if (strokeMarks.isNotEmpty) {
        final start = compositedCount.clamp(0, strokeMarks.length);
        for (int i = start; i < strokeMarks.length; i++) {
          _drawStrokeMark(offscreen, compositedImage!, strokeMarks[i]);
        }
      }
      // committed 阶段：已全部在基底层中，无需再画
    } else if (srcImg != null) {
      // 无 GPU 合成结果：全部从 sourceImage 采样
      final allPreview = <HealingMark>[...strokeMarks, ...committedMarks];
      for (final mark in allPreview) {
        _drawStrokeMark(offscreen, srcImg, mark);
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

    // 实时光标预览：与 marks 使用一致的 base
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

    // 画布变换到目标中心，后续以原点为参考
    canvas.save();
    canvasApplyCrop(canvas, screenCenter, crop);

    // OOB 映射（原点即画布原点 = 屏幕目标中心）
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
      hardness: mark.hardness,
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

    // OOB 映射（原点即画布原点 = 屏幕光标中心）
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
      old.compositedImage != compositedImage ||
      old.compositedCount != compositedCount ||
      !listEquals(old.strokeMarks, strokeMarks) ||
      !listEquals(old.committedMarks, committedMarks) ||
      old.imageDisplaySize != imageDisplaySize ||
      old.crop != crop ||
      old.sourceWidth != sourceWidth ||
      old.sourceHeight != sourceHeight;
}
