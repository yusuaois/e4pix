import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 污点修复标记（真正的 Spot Healing Brush）。
///
/// 用户画圈选中缺陷，工具自动从圈外边界采样像素填充圈内。
/// 与图章（Clone Stamp）不同：无需手动 Alt+取样指定源点。
@immutable
class SpotHealMark {
  /// 目标圆心（归一化 [0..1] 全图坐标）
  final Offset target;

  /// 半径（归一化，相对于源图宽度）
  final double radius;

  /// 硬度：1=硬边 step，0=软边 smoothstep 全半径
  final double hardness;

  const SpotHealMark({
    required this.target,
    this.radius = 0.02,
    this.hardness = 1.0,
  });

  SpotHealMark copyWith({Offset? target, double? radius, double? hardness}) {
    return SpotHealMark(
      target: target ?? this.target,
      radius: radius ?? this.radius,
      hardness: hardness ?? this.hardness,
    );
  }

  Map<String, dynamic> toJson() => {
    'targetX': target.dx,
    'targetY': target.dy,
    'radius': radius,
    'hardness': hardness,
  };

  factory SpotHealMark.fromJson(Map<String, dynamic> json) {
    return SpotHealMark(
      target: Offset(
        (json['targetX'] as num).toDouble(),
        (json['targetY'] as num).toDouble(),
      ),
      radius: (json['radius'] as num).toDouble(),
      hardness: (json['hardness'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpotHealMark &&
      other.target == target &&
      other.radius == radius &&
      other.hardness == hardness;

  @override
  int get hashCode => Object.hash(target, radius, hardness);
}
