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
