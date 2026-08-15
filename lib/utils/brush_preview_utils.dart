import 'dart:math' as math;
import 'dart:ui';

import '../core/models/crop_params.dart';

/// 画布变换到 [center] 并应用裁剪旋转和翻转
///
/// 调用方需自行 canvas.save / canvas.restore
void canvasApplyCrop(Canvas canvas, Offset center, CropParams crop) {
  canvas.translate(center.dx, center.dy);
  final angle =
      crop.orientation * math.pi / 2 + crop.straighten * math.pi / 180;
  if (angle != 0) canvas.rotate(angle);
  if (crop.flipH || crop.flipV) {
    canvas.scale(crop.flipH ? -1.0 : 1.0, crop.flipV ? -1.0 : 1.0);
  }
}

/// 把「裁剪前」源图按 crop 画到「裁剪后」显示区，镜像 applyCropTransform
///
/// image 归一化内容与源图一致，像素尺寸不同；sourceWidth/Height 为原始全图尺寸
void drawSourceImageCropped({
  required Canvas canvas,
  required Image image,
  required CropParams crop,
  required int sourceWidth,
  required int sourceHeight,
  required Size displaySize,
  required Paint paint,
}) {
  if (crop.isIdentity) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, displaySize.width, displaySize.height),
      paint,
    );
    return;
  }

  final swap = crop.orientationSwapsAxes;
  final orientedW = (swap ? sourceHeight : sourceWidth).toDouble();
  final orientedH = (swap ? sourceWidth : sourceHeight).toDouble();
  final cropW = crop.width * orientedW;
  final cropH = crop.height * orientedH;

  canvas.save();
  // 逆序构建「源图坐标 → 裁剪后显示坐标」的 canvas 变换（等价 applyCropTransform 两步）
  canvas.scale(displaySize.width / cropW, displaySize.height / cropH);
  canvas.translate(-crop.x * orientedW, -crop.y * orientedH);
  canvas.translate(orientedW / 2, orientedH / 2);
  canvas.rotate(
    crop.orientation * math.pi / 2 + crop.straighten * math.pi / 180,
  );
  canvas.scale(crop.flipH ? -1.0 : 1.0, crop.flipV ? -1.0 : 1.0);
  canvas.translate(-sourceWidth / 2, -sourceHeight / 2);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, sourceWidth.toDouble(), sourceHeight.toDouble()),
    paint,
  );
  canvas.restore();
}

/// 计算 OOB（Out-of-Bounds）比例映射矩形
///
/// 当采样源矩形部分超出图像边界时，计算采样区域与图像边界的交集，
/// 并按比例映射到目标圆内的对应区域,界外部分透明（不拉伸边缘像素）
///
/// 参数：
/// - [sxRaw]/[syRaw]: 源像素中心坐标（像素空间）
/// - [pr]: 源像素半径
/// - [imageW]/[imageH]: 源图像宽高（像素）
/// - [screenCenterX]/[screenCenterY]: 目标圆在屏幕空间的中心坐标
/// - [screenR]: 目标圆屏幕半径
///
/// 返回 null 表示采样区域完全在图像外，无需绘制
/// 返回 record 包含：
/// - `srcRect`: 有效采样区域（源图像内的交集部分）
/// - `dstRect`: 在目标圆内对应的映射区域
/// - `fullDstRect`: 完整目标圆的外接矩形（用于 clip）
({Rect srcRect, Rect dstRect, Rect fullDstRect})? computeOOBRects({
  required double sxRaw,
  required double syRaw,
  required double pr,
  required double imageW,
  required double imageH,
  required double screenCenterX,
  required double screenCenterY,
  required double screenR,
}) {
  final rawLeft = sxRaw - pr;
  final rawTop = syRaw - pr;
  final rawRight = sxRaw + pr;
  final rawBottom = syRaw + pr;
  final rawSize = pr * 2;

  final clLeft = rawLeft.clamp(0.0, imageW);
  final clTop = rawTop.clamp(0.0, imageH);
  final clRight = rawRight.clamp(0.0, imageW);
  final clBottom = rawBottom.clamp(0.0, imageH);

  if (clRight <= clLeft || clBottom <= clTop) return null;

  final srcRect = Rect.fromLTRB(clLeft, clTop, clRight, clBottom);
  final leftFrac = (clLeft - rawLeft) / rawSize;
  final topFrac = (clTop - rawTop) / rawSize;
  final rightFrac = (clRight - rawLeft) / rawSize;
  final bottomFrac = (clBottom - rawTop) / rawSize;
  final dstSize = screenR * 2;
  final dstRect = Rect.fromLTRB(
    screenCenterX - screenR + leftFrac * dstSize,
    screenCenterY - screenR + topFrac * dstSize,
    screenCenterX - screenR + rightFrac * dstSize,
    screenCenterY - screenR + bottomFrac * dstSize,
  );
  final fullDstRect = Rect.fromCircle(
    center: Offset(screenCenterX, screenCenterY),
    radius: screenR,
  );
  return (srcRect: srcRect, dstRect: dstRect, fullDstRect: fullDstRect);
}

/// 判断 brush mark 的取样圆是否完全在源图外
///
/// 用于在 GPU 编码前预过滤——[_packFloat16] 夹持归一化坐标到 [0,1]，
/// shader OOB 守卫无法区分"真 OOB"和"被夹持到边缘的值"
/// 使用 AABB 近似（保守检查）：零假阳性，角落假阴性由 shader per-pixel 处理
/// [sourceX]/[sourceY] 归一化 [0..1] 坐标（可越界）
/// [radius] 归一化半径，按 [imageWidth] 换算到像素
bool isMarkSourceFullyOOB({
  required double sourceX,
  required double sourceY,
  required double radius,
  required double imageWidth,
  required double imageHeight,
}) {
  final pr = (radius * imageWidth).clamp(1.0, imageWidth / 2.0);
  final sxRaw = sourceX * imageWidth;
  final syRaw = sourceY * imageHeight;
  return sxRaw + pr <= 0 ||
      sxRaw - pr >= imageWidth ||
      syRaw + pr <= 0 ||
      syRaw - pr >= imageHeight;
}

const _kWhite = Color(0xFFFFFFFF);
const _kTransparent = Color(0x00000000);

/// 绘制带径向渐变柔边的圆形图像 stamp（含硬边快速路径）
///
/// Canvas 需已通过 [canvasApplyCrop] 变换到目标中心
/// [hardness] 0=最软 1=硬边；≥0.999 走硬边路径
void drawSoftEdgeStamp({
  required Canvas canvas,
  required Image image,
  required ({Rect srcRect, Rect dstRect, Rect fullDstRect}) rects,
  required double hardness,
  required double screenRadius,
  required Paint imagePaint,
}) {
  if (hardness >= 0.999) {
    canvas.clipPath(Path()..addOval(rects.fullDstRect));
    canvas.drawImageRect(image, rects.srcRect, rects.dstRect, imagePaint);
    return;
  }
  final t0 = hardness.clamp(0.0, 1.0);
  final span = 1.0 - t0;
  double ss(double t) => (3 * t * t - 2 * t * t * t).clamp(0.0, 1.0);
  final gradient = Gradient.radial(
    Offset.zero,
    screenRadius,
    [
      _kWhite,
      if (span > 0.01) ...[
        _kWhite,
        Color(((255 * (1 - ss(0.25))).round() << 24) | 0xFFFFFF),
        Color(((255 * (1 - ss(0.5))).round() << 24) | 0xFFFFFF),
        Color(((255 * (1 - ss(0.75))).round() << 24) | 0xFFFFFF),
      ],
      _kTransparent,
    ],
    [
      0.0,
      if (span > 0.01) ...[
        t0,
        t0 + span * 0.25,
        t0 + span * 0.5,
        t0 + span * 0.75,
      ],
      1.0,
    ],
  );
  canvas.clipPath(Path()..addOval(rects.fullDstRect));
  canvas.saveLayer(rects.fullDstRect.inflate(2.0), Paint());
  canvas.drawImageRect(image, rects.srcRect, rects.dstRect, imagePaint);
  canvas.drawRect(
    rects.fullDstRect,
    Paint()
      ..shader = gradient
      ..blendMode = BlendMode.dstIn,
  );
  canvas.restore();
}
