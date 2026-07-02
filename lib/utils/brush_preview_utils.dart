import 'dart:ui';

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
