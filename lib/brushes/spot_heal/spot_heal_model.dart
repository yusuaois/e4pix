import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../shared/stamp/stamp_mark.dart';

/// 污点修复标记（真正的 Spot Healing Brush）
///
/// 用户画圈选中缺陷，工具自动从圈外边界采样像素填充圈内
/// 与图章（Clone Stamp）不同：无需手动 Alt+取样指定源点
@immutable
class SpotHealMark implements StampMark {
  /// 无源点偏移：效果类画笔从同位置处理
  @override
  Offset get source => target;

  /// 目标圆心（归一化 [0..1] 全图坐标）
  @override
  final Offset target;

  /// 半径（归一化，相对于源图宽度）
  @override
  final double radius;

  /// 硬度：1=硬边 step，0=软边 smoothstep 全半径
  @override
  final double hardness;

  @override
  final DateTime createdAt;

  const SpotHealMark({
    required this.target,
    required this.createdAt,
    this.radius = 0.02,
    this.hardness = 1.0,
  });

  SpotHealMark copyWith({
    Offset? target,
    double? radius,
    double? hardness,
    DateTime? createdAt,
  }) {
    return SpotHealMark(
      target: target ?? this.target,
      radius: radius ?? this.radius,
      hardness: hardness ?? this.hardness,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'targetX': target.dx,
    'targetY': target.dy,
    'radius': radius,
    'hardness': hardness,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory SpotHealMark.fromJson(Map<String, dynamic> json) {
    final createdAt = StampMark.parseCreatedAt(json);
    return SpotHealMark(
      target: Offset(
        (json['targetX'] as num?)?.toDouble() ?? 0.0,
        (json['targetY'] as num?)?.toDouble() ?? 0.0,
      ),
      radius: (json['radius'] as num?)?.toDouble() ?? 0.02,
      hardness: (json['hardness'] as num?)?.toDouble() ?? 1.0,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpotHealMark &&
      other.target == target &&
      other.radius == radius &&
      other.hardness == hardness &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(target, radius, hardness, createdAt);
}
