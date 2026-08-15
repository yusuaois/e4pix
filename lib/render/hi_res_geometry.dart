import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 分段渲染超清的几何计算（纯函数，无 GPU 依赖，可单测）
///
/// 坐标系约定（与 `docs/rendering/RENDERING_RULES.md` 一致）：
/// - 主预览显示的底图 `_rendered` 是「裁剪后输出图」（crop 已在管线内完成）
/// - `displaySize` 是裁剪后输出图按 BoxFit.contain 缩放到屏幕的显示尺寸
/// - `viewportTransform` 是 InteractiveViewer 的 child→viewport 变换矩阵
///   （即 `viewportTransformProvider` 的值，与 `_ColorReadout` 用法对称）

/// 瓦片长边上限（防单瓦片内存失控）
const int kHiResTileMaxEdge = 4096;

/// 视口可见区域 → 全尺寸裁剪后输出图的源矩形 + displaySize 坐标的目标矩形
///
/// 返回 null 表示当前无可见区域（如空交集）：
/// - [src]：全尺寸裁剪后输出图（`fullOutSize`）中需要切出的源矩形
/// - [dst]：displaySize 坐标中瓦片应放置的矩形
///
/// 对齐数学（与 `preview_area.dart` `_buildViewportReadout` 对称）：
/// `viewportTransform` 是 child→viewport，求逆得 viewport→child；
/// child 是 `Center` 占满 viewport 的空间，减 `Center` 居中偏移后得 display 坐标。
({Rect src, Rect dst})? computeTileRects({
  required Matrix4 viewportTransform,
  required Size viewportSize,
  required Size displaySize,
  required Size fullOutSize,
}) {
  final inv = Matrix4.tryInvert(viewportTransform);
  if (inv == null) return null;

  final corners = [
    Offset.zero,
    Offset(viewportSize.width, 0),
    Offset(0, viewportSize.height),
    Offset(viewportSize.width, viewportSize.height),
  ].map((c) => MatrixUtils.transformPoint(inv, c)).toList();

  final minX = corners.map((c) => c.dx).reduce(math.min);
  final maxX = corners.map((c) => c.dx).reduce(math.max);
  final minY = corners.map((c) => c.dy).reduce(math.min);
  final maxY = corners.map((c) => c.dy).reduce(math.max);

  // Center 空间坐标 → display 坐标：减居中偏移
  final centerDx = (viewportSize.width - displaySize.width) / 2;
  final centerDy = (viewportSize.height - displaySize.height) / 2;

  final left = (minX - centerDx).clamp(0.0, displaySize.width);
  final top = (minY - centerDy).clamp(0.0, displaySize.height);
  final right = (maxX - centerDx).clamp(0.0, displaySize.width);
  final bottom = (maxY - centerDy).clamp(0.0, displaySize.height);

  if (right - left < 1 || bottom - top < 1) return null;

  final sx = fullOutSize.width / displaySize.width;
  final sy = fullOutSize.height / displaySize.height;

  return (
    src: Rect.fromLTRB(left * sx, top * sy, right * sx, bottom * sy),
    dst: Rect.fromLTRB(left, top, right, bottom),
  );
}

/// 瓦片分辨率：min(源矩形像素, 屏上物理像素 × oversample)，封顶 [kHiResTileMaxEdge]
///
/// 这样 zoom 较低时瓦片不会切出整张全尺寸图（省内存），
/// 而 zoom 到 100%（真实像素）时瓦片像素 = 源像素，达成「看到真实像素」。
({int w, int h}) tileResolution({
  required Rect src,
  required Rect dst,
  required double zoom,
  required double devicePixelRatio,
  double oversample = 2.0,
}) {
  final onScreenW = dst.width * zoom * devicePixelRatio;
  final onScreenH = dst.height * zoom * devicePixelRatio;

  final w = math
      .min(src.width, onScreenW * oversample)
      .ceil()
      .clamp(1, kHiResTileMaxEdge)
      .toInt();
  final h = math
      .min(src.height, onScreenH * oversample)
      .ceil()
      .clamp(1, kHiResTileMaxEdge)
      .toInt();
  return (w: w, h: h);
}

/// 从全尺寸裁剪后输出图切出 [src] 区域，缩放到 [w]×[h]
Future<ui.Image> extractTile(
  ui.Image fullCropped,
  Rect src,
  int w,
  int h,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    fullCropped,
    src,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}
