import 'package:flutter/foundation.dart';

@immutable
class CropParams {
  /// 归一化坐标 [0..1]
  final double x;
  final double y;
  final double width;
  final double height;

  const CropParams({
    this.x = 0.0,
    this.y = 0.0,
    this.width = 1.0,
    this.height = 1.0,
  });

  static const identity = CropParams();

  bool get isIdentity =>
      x == 0.0 && y == 0.0 && width == 1.0 && height == 1.0;

  double get aspect => width <= 0 || height <= 0 ? 1.0 : width / height;

  CropParams copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) =>
      CropParams(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  /// 锁定纵横比时围绕中心
  CropParams resizeKeepingAspectRatio(double sourceAspectRatio,
      {required double newWidth, required double targetAspect}) {
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
      };

  factory CropParams.fromJson(Map<String, dynamic> j) => CropParams(
        x: (j['x'] as num?)?.toDouble() ?? 0.0,
        y: (j['y'] as num?)?.toDouble() ?? 0.0,
        width: (j['width'] as num?)?.toDouble() ?? 1.0,
        height: (j['height'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CropParams &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height);

  @override
  int get hashCode => Object.hash(x, y, width, height);
}