import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/models/crop_params.dart';
import '../../../utils/brush_coord_utils.dart';
import '../../../utils/brush_preview_utils.dart';
import 'stamp_mark.dart';
import 'stamp_painter_utils.dart';

/// 源-目标型画笔的共享 Painter 基类，泛型参数 [T] 为 mark 类型
///
/// 封装三层离屏渲染、四种光标绘制、OOB 图章绘制及 [shouldRepaint]
/// 子类只需转发构造函数参数
abstract class BaseStampPainter<T extends StampMark> extends CustomPainter {
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
  final List<T> strokeMarks;
  final List<T> committedMarks;

  static final _imagePaint = Paint()..filterQuality = FilterQuality.medium;

  BaseStampPainter({
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
    final hasComposited = compositedImage != null;
    final srcImg = sourceImage;

    final recorder = ui.PictureRecorder();
    final offscreen = Canvas(recorder);

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

      if (strokeMarks.isNotEmpty) {
        final start = compositedCount.clamp(0, strokeMarks.length);
        for (int i = start; i < strokeMarks.length; i++) {
          _drawStrokeMark(offscreen, compositedImage!, strokeMarks[i]);
        }
      }
    } else if (srcImg != null) {
      final allPreview = <T>[...strokeMarks, ...committedMarks];
      for (final mark in allPreview) {
        _drawStrokeMark(offscreen, srcImg, mark);
      }
    }

    final didDraw =
        (hasComposited && compositedImage != null) || srcImg != null;
    if (didDraw) {
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

    final cursorBase = sourceImage;

    if (isSampling) {
      drawSamplingUI(canvas, cursorPos!, r);
    } else if (!isPainting && cloneSource != null && cursorBase != null) {
      final previewSrc = paintOffset != null
          ? Offset(
              cursorSrc!.dx + paintOffset!.dx,
              cursorSrc!.dy + paintOffset!.dy,
            )
          : cloneSource!;
      drawPreviewCursor(
        canvas: canvas,
        screenPos: cursorPos!,
        screenRadius: r,
        srcNorm: previewSrc,
        baseImage: cursorBase,
        brushRadius: brushRadius,
        brushHardness: brushHardness,
        crop: crop,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        imagePaint: _imagePaint,
      );
    } else {
      drawTargetCursor(canvas, cursorPos!, r);
    }
    if (!isSampling && isPainting && cloneSource != null) {
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
      drawSourceCrosshair(canvas, srcScreen);
    }
  }

  void _drawStrokeMark(Canvas canvas, ui.Image img, T mark) {
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
      hardness: mark.hardness,
      screenRadius: screenR,
      imagePaint: _imagePaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BaseStampPainter<T> old) =>
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
