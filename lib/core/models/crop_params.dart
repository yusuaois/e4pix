import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

@immutable
class CropParams {
  /// 裁剪框 归一化坐标 [0..1]
  final double x;
  final double y;
  final double width;
  final double height;

  /// 90° 增量旋转 0/1/2/3 -> 0°/90° CW/180°/270° CW
  final int orientation;

  /// 拉直微调 [-45..+45]
  final double straighten;

  /// 翻转
  final bool flipH;
  final bool flipV;

  const CropParams({
    this.x = 0.0,
    this.y = 0.0,
    this.width = 1.0,
    this.height = 1.0,
    this.orientation = 0,
    this.straighten = 0.0,
    this.flipH = false,
    this.flipV = false,
  });

  static const identity = CropParams();

  bool get isIdentity =>
      x == 0.0 &&
      y == 0.0 &&
      width == 1.0 &&
      height == 1.0 &&
      orientation == 0 &&
      straighten == 0.0 &&
      !flipH &&
      !flipV;

  /// "源图像被 orientation 转过之后" 的纵横比相对于原始的关系
  /// 0/2 = 横竖比不变；1/3 = 倒置
  bool get orientationSwapsAxes => orientation % 2 == 1;

  /// 逆裁剪：输出像素坐标 → 全图坐标（浮点，双线性插值用）
  ///
  /// [ox]/[oy] 输出像素坐标，[outW]/[outH] 输出尺寸
  /// [srcW]/[srcH] 原始全图尺寸
  /// 返回值是全图坐标系中的浮点坐标
  (double, double) inverseMap(
    double ox,
    double oy,
    int outW,
    int outH,
    int srcW,
    int srcH,
  ) {
    final nx = (ox + 0.5) / outW;
    final ny = (oy + 0.5) / outH;

    final swap = orientationSwapsAxes;
    final orientedW = swap ? srcH : srcW;
    final orientedH = swap ? srcW : srcH;

    var ix = (x + nx * width) * orientedW;
    var iy = (y + ny * height) * orientedH;

    final cx = orientedW / 2.0;
    final cy = orientedH / 2.0;
    ix -= cx;
    iy -= cy;

    if (straighten != 0) {
      final angle = -straighten * math.pi / 180;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      final rx = ix * cos - iy * sin;
      final ry = ix * sin + iy * cos;
      ix = rx;
      iy = ry;
    }

    for (int i = 0; i < (4 - orientation) % 4; i++) {
      final rx = -iy;
      iy = ix;
      ix = rx;
    }

    if (flipH) ix = -ix;
    if (flipV) iy = -iy;

    ix += srcW / 2.0;
    iy += srcH / 2.0;
    return (ix, iy);
  }

  /// 输出归一化坐标 [0..1] → 全图归一化坐标 [0..1]
  ///
  /// 与 [inverseMap] 相同的逆变换，但输入输出都是归一化连续坐标
  /// 不含像素中心偏移 用于将屏幕点击坐标（裁剪后空间）变换到
  /// 全图空间，供 SAM / SmartRegion 在全图 guide 上定位种子点
  (double, double) outputToSourceNorm(
    double nx,
    double ny,
    int srcW,
    int srcH,
  ) {
    if (isIdentity) return (nx, ny);

    final swap = orientationSwapsAxes;
    final ow = swap ? srcH : srcW;
    final oh = swap ? srcW : srcH;

    // 归一化 → oriented 像素坐标
    var ix = (x + nx * width) * ow;
    var iy = (y + ny * height) * oh;

    // 反变换（与 inverseMap 一致，中心 = oriented 图像中心）
    ix -= ow / 2.0;
    iy -= oh / 2.0;

    if (straighten != 0) {
      final angle = -straighten * math.pi / 180;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      final rx = ix * cos - iy * sin;
      final ry = ix * sin + iy * cos;
      ix = rx;
      iy = ry;
    }

    for (int i = 0; i < (4 - orientation) % 4; i++) {
      final rx = -iy;
      iy = ix;
      ix = rx;
    }

    if (flipH) ix = -ix;
    if (flipV) iy = -iy;

    ix += srcW / 2.0;
    iy += srcH / 2.0;
    return (ix / srcW, iy / srcH);
  }

  /// [outputToSourceNorm] 的 Offset 便捷版本
  ui.Offset outputToSourceOffset(ui.Offset seed, int srcW, int srcH) {
    final (sx, sy) = outputToSourceNorm(seed.dx, seed.dy, srcW, srcH);
    return ui.Offset(sx, sy);
  }

  /// 正向变换：归一化源图坐标 [0..1] → 归一化输出坐标 [0..1]
  ///
  /// 与 [outputToSourceNorm] 互为逆运算。
  /// 用于将污点标记（源图坐标）映射到屏幕显示位置。
  (double, double) forwardToOutputNorm(
    double sx,
    double sy,
    int srcW,
    int srcH,
  ) {
    if (isIdentity) return (sx, sy);

    final swap = orientationSwapsAxes;
    final ow = swap ? srcH : srcW;
    final oh = swap ? srcW : srcH;

    // 源图归一化 → 源图像素（以中心为原点）
    var px = sx * srcW - srcW / 2.0;
    var py = sy * srcH - srcH / 2.0;

    // flip（逆变换中先 flip，正向也先 flip）
    if (flipH) px = -px;
    if (flipV) py = -py;

    // orientation 正向旋转 CW
    for (int i = 0; i < orientation % 4; i++) {
      final ry = -px;
      px = py;
      py = ry;
    }

    // straighten 正向旋转
    if (straighten != 0) {
      final angle = straighten * math.pi / 180;
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      final rx = px * cos - py * sin;
      final ry = px * sin + py * cos;
      px = rx;
      py = ry;
    }

    // 加回 oriented 中心
    px += ow / 2.0;
    py += oh / 2.0;

    // oriented 像素 → 输出归一化
    final onx = (px / ow - x) / width;
    final ony = (py / oh - y) / height;
    return (onx, ony);
  }

  /// 在裁剪下，输出画面的布局纵横比
  double outAspectFor(double srcW, double srcH) {
    final w = orientationSwapsAxes ? srcH : srcW;
    final h = orientationSwapsAxes ? srcW : srcH;
    return (w * width) / (h * height);
  }

  CropParams copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    int? orientation,
    double? straighten,
    bool? flipH,
    bool? flipV,
  }) => CropParams(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    orientation: orientation ?? this.orientation,
    straighten: straighten ?? this.straighten,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
  );

  /// 锁定纵横比时围绕中心
  CropParams resizeKeepingAspectRatio(
    double sourceAspectRatio, {
    required double newWidth,
    required double targetAspect,
  }) {
    final newHeight = (newWidth * sourceAspectRatio) / targetAspect;
    final cx = x + width / 2;
    final cy = y + height / 2;
    var nx = cx - newWidth / 2;
    var ny = cy - newHeight / 2;
    nx = nx.clamp(0.0, 1.0 - newWidth);
    ny = ny.clamp(0.0, 1.0 - newHeight);
    return CropParams(x: nx, y: ny, width: newWidth, height: newHeight);
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'orientation': orientation,
    'straighten': straighten,
    'flipH': flipH,
    'flipV': flipV,
  };

  factory CropParams.fromJson(Map<String, dynamic> j) => CropParams(
    x: (j['x'] as num?)?.toDouble() ?? 0.0,
    y: (j['y'] as num?)?.toDouble() ?? 0.0,
    width: (j['width'] as num?)?.toDouble() ?? 1.0,
    height: (j['height'] as num?)?.toDouble() ?? 1.0,
    orientation: (j['orientation'] as num?)?.toInt() ?? 0,
    straighten: (j['straighten'] as num?)?.toDouble() ?? 0.0,
    flipH: j['flipH'] as bool? ?? false,
    flipV: j['flipV'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CropParams &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          orientation == other.orientation &&
          straighten == other.straighten &&
          flipH == other.flipH &&
          flipV == other.flipV);

  @override
  int get hashCode =>
      Object.hash(x, y, width, height, orientation, straighten, flipH, flipV);
}
