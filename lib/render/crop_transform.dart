import 'dart:math' as math;
import 'dart:ui' as ui;

import '../core/models/crop_params.dart';

/// 计算裁剪后输出尺寸，镜像 applyCropTransform 的尺寸逻辑（纯函数）
///
/// 尺寸仅由 width/height × orientation 轴交换后尺寸决定，与 x/y/straighten/flip 无关
ui.Size cropOutputSize(CropParams crop, int srcW, int srcH) {
  final swap = crop.orientationSwapsAxes;
  final orientedW = swap ? srcH : srcW;
  final orientedH = swap ? srcW : srcH;
  return ui.Size(
    (crop.width * orientedW).roundToDouble(),
    (crop.height * orientedH).roundToDouble(),
  );
}

/// 应用 crop 变换（orientation + flip + straighten + 裁剪框）
/// 返回新 ui.Image 用于 export / histogram 等
Future<ui.Image> applyCropTransform(ui.Image src, CropParams crop) async {
  if (crop.isIdentity) return _cloneImage(src);

  // orientation + flip + straighten 变换 → 中间 image
  // 中间 image 的画布大小就是 src 经过这些变换后的紧致包围矩形
  final stage1 = await _applyOrientationFlipStraighten(src, crop);

  // 在中间 image 上裁剪
  if (crop.x == 0 && crop.y == 0 && crop.width == 1 && crop.height == 1) {
    return stage1;
  }
  final cropped = await _cropRect(stage1, crop);
  stage1.dispose();
  return cropped;
}

Future<ui.Image> _applyOrientationFlipStraighten(
  ui.Image src,
  CropParams crop,
) async {
  // 90° orientation 决定中间 image 的轴交换
  final swapAxes = crop.orientationSwapsAxes;
  // crop rect 自行内收
  final orientedW = swapAxes ? src.height : src.width;
  final orientedH = swapAxes ? src.width : src.height;

  final pr = ui.PictureRecorder();
  final canvas = ui.Canvas(pr);

  // canvas 中心对齐 (orientedW/2, orientedH/2)，
  // translate to center → rotate (orientation + straighten) → flip → translate back
  canvas.translate(orientedW / 2, orientedH / 2);
  canvas.rotate(
    crop.orientation * math.pi / 2 + crop.straighten * math.pi / 180,
  );
  canvas.scale(crop.flipH ? -1.0 : 1.0, crop.flipV ? -1.0 : 1.0);
  canvas.translate(-src.width / 2, -src.height / 2);
  canvas.drawImage(
    src,
    ui.Offset.zero,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );

  final picture = pr.endRecording();
  return picture.toImage(orientedW, orientedH);
}

Future<ui.Image> _cropRect(ui.Image src, CropParams crop) async {
  final w = src.width.toDouble();
  final h = src.height.toDouble();
  final srcRect = ui.Rect.fromLTWH(
    crop.x * w,
    crop.y * h,
    crop.width * w,
    crop.height * h,
  );
  final outW = srcRect.width.round();
  final outH = srcRect.height.round();
  final dstRect = ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());

  final pr = ui.PictureRecorder();
  ui.Canvas(pr).drawImageRect(src, srcRect, dstRect, ui.Paint());
  final picture = pr.endRecording();
  return picture.toImage(outW, outH);
}

ui.Image _cloneImage(ui.Image src) => src.clone();
