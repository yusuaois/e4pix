import 'package:flutter/foundation.dart';

/// 透视/梯形校正参数
///
/// 支持两种模式：
/// 1. 四角偏移模式：[topLeft]～[bottomLeft] 为归一化坐标偏移 [-0.5, +0.5]
/// 2. 梯形角模式：从 [horizontalKeystone] / [verticalKeystone] 自动推导四角
@immutable
class PerspectiveParams {
  /// 四角偏移（归一化，相对原始角的偏移）
  /// 顺序：左上，右上，右下，左下
  final double topLeftX;
  final double topLeftY;
  final double topRightX;
  final double topRightY;
  final double bottomRightX;
  final double bottomRightY;
  final double bottomLeftX;
  final double bottomLeftY;

  const PerspectiveParams({
    this.topLeftX = 0.0,
    this.topLeftY = 0.0,
    this.topRightX = 0.0,
    this.topRightY = 0.0,
    this.bottomRightX = 0.0,
    this.bottomRightY = 0.0,
    this.bottomLeftX = 0.0,
    this.bottomLeftY = 0.0,
  });

  static const identity = PerspectiveParams();

  bool get isIdentity =>
      topLeftX == 0.0 &&
      topLeftY == 0.0 &&
      topRightX == 0.0 &&
      topRightY == 0.0 &&
      bottomRightX == 0.0 &&
      bottomRightY == 0.0 &&
      bottomLeftX == 0.0 &&
      bottomLeftY == 0.0;

  /// 四个源点（归一化坐标）
  List<({double x, double y})> get sourceQuad => [
    (x: 0.0 + topLeftX, y: 0.0 + topLeftY),
    (x: 1.0 + topRightX, y: 0.0 + topRightY),
    (x: 1.0 + bottomRightX, y: 1.0 + bottomRightY),
    (x: 0.0 + bottomLeftX, y: 1.0 + bottomLeftY),
  ];

  /// 四个目标点（归一化，矩形）
  static const destQuad = [
    (x: 0.0, y: 0.0),
    (x: 1.0, y: 0.0),
    (x: 1.0, y: 1.0),
    (x: 0.0, y: 1.0),
  ];

  /// 从梯形角度创建偏移
  /// [horizontal] 和 [vertical] 单位为角度（度），范围 [-60, 60]
  factory PerspectiveParams.fromKeystone({
    double horizontal = 0.0,
    double vertical = 0.0,
  }) {
    const maxOffset = 0.5;
    final hOff = (horizontal / 60.0 * maxOffset).clamp(-maxOffset, maxOffset);
    final vOff = (vertical / 60.0 * maxOffset).clamp(-maxOffset, maxOffset);

    return PerspectiveParams(
      topLeftX: -hOff,
      topRightX: hOff,
      bottomLeftX: -hOff,
      bottomRightX: hOff,
      topLeftY: -vOff,
      topRightY: -vOff,
      bottomLeftY: vOff,
      bottomRightY: vOff,
    );
  }

  PerspectiveParams copyWith({
    double? topLeftX,
    double? topLeftY,
    double? topRightX,
    double? topRightY,
    double? bottomRightX,
    double? bottomRightY,
    double? bottomLeftX,
    double? bottomLeftY,
  }) =>
      PerspectiveParams(
        topLeftX: topLeftX ?? this.topLeftX,
        topLeftY: topLeftY ?? this.topLeftY,
        topRightX: topRightX ?? this.topRightX,
        topRightY: topRightY ?? this.topRightY,
        bottomRightX: bottomRightX ?? this.bottomRightX,
        bottomRightY: bottomRightY ?? this.bottomRightY,
        bottomLeftX: bottomLeftX ?? this.bottomLeftX,
        bottomLeftY: bottomLeftY ?? this.bottomLeftY,
      );

  /// 便捷：水平梯形偏移
  PerspectiveParams withHorizontalKeystone(double degrees) =>
      PerspectiveParams.fromKeystone(
        horizontal: degrees,
        vertical: currentVertical(),
      );

  PerspectiveParams withVerticalKeystone(double degrees) =>
      PerspectiveParams.fromKeystone(
        horizontal: currentHorizontal(),
        vertical: degrees,
      );

  double currentHorizontal() {
    // topLeftX = -hOff, topRightX = +hOff → (topRightX - topLeftX)/2 = hOff
    final hOff = (topLeftX + topRightX) / 2;
    // topRightX is the primary indicator for horizontal keystone
    final actual = topRightX.abs() > 0.001 ? topRightX : hOff;
    return (actual / 0.5 * 60).clamp(-60.0, 60.0);
  }

  double currentVertical() {
    // bottomLeftY = +vOff, topLeftY = -vOff → (bottomLeftY - topLeftY)/2 = vOff
    final vOff = (bottomLeftY + bottomRightY) / 2;
    final actual = bottomLeftY.abs() > 0.001 ? bottomLeftY : vOff;
    return (actual / 0.5 * 60).clamp(-60.0, 60.0);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerspectiveParams &&
          topLeftX == other.topLeftX &&
          topLeftY == other.topLeftY &&
          topRightX == other.topRightX &&
          topRightY == other.topRightY &&
          bottomRightX == other.bottomRightX &&
          bottomRightY == other.bottomRightY &&
          bottomLeftX == other.bottomLeftX &&
          bottomLeftY == other.bottomLeftY;

  @override
  int get hashCode => Object.hashAll([
    topLeftX,
    topLeftY,
    topRightX,
    topRightY,
    bottomRightX,
    bottomRightY,
    bottomLeftX,
    bottomLeftY,
  ]);

  Map<String, dynamic> toJson() => {
    'topLeftX': topLeftX,
    'topLeftY': topLeftY,
    'topRightX': topRightX,
    'topRightY': topRightY,
    'bottomRightX': bottomRightX,
    'bottomRightY': bottomRightY,
    'bottomLeftX': bottomLeftX,
    'bottomLeftY': bottomLeftY,
  };

  factory PerspectiveParams.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0.0;
    return PerspectiveParams(
      topLeftX: d('topLeftX'),
      topLeftY: d('topLeftY'),
      topRightX: d('topRightX'),
      topRightY: d('topRightY'),
      bottomRightX: d('bottomRightX'),
      bottomRightY: d('bottomRightY'),
      bottomLeftX: d('bottomLeftX'),
      bottomLeftY: d('bottomLeftY'),
    );
  }
}
