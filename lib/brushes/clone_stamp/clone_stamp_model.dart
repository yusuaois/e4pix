import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../shared/stamp/stamp_mark.dart';

/// 污点修复标记（仿制图章）
///
/// 用户在预览图上标记一个污点区域（[target]），并指定采样源区域（[source]）
/// 渲染时将 [source] 处的像素克隆到 [target] 处，以 [radius] 为半径带柔边混合
/// 所有坐标均为归一化 [0..1]，相对于源图（非裁剪后）坐标系
@immutable
class SpotMark implements StampMark {
  /// 采样源位置（归一化 [0..1]，源图坐标系）
  @override
  final Offset source;

  /// 修复目标位置（归一化 [0..1]，源图坐标系）
  @override
  final Offset target;

  /// 修复半径（归一化，相对源图宽度），默认 0.02 = 源图宽度的 2%
  @override
  final double radius;

  /// 边缘硬度 0..1，1=硬边，0=柔边
  @override
  final double hardness;

  const SpotMark({
    required this.source,
    required this.target,
    this.radius = 0.02,
    this.hardness = 1.0,
  });

  @override
  Map<String, dynamic> toJson() => {
    'source': [source.dx, source.dy],
    'target': [target.dx, target.dy],
    'radius': radius,
    'hardness': hardness,
  };

  factory SpotMark.fromJson(Map<String, dynamic> j) {
    final src = j['source'] as List?;
    final tgt = j['target'] as List?;
    return SpotMark(
      source: src != null && src.length >= 2
          ? Offset((src[0] as num).toDouble(), (src[1] as num).toDouble())
          : Offset.zero,
      target: tgt != null && tgt.length >= 2
          ? Offset((tgt[0] as num).toDouble(), (tgt[1] as num).toDouble())
          : Offset.zero,
      radius: (j['radius'] as num?)?.toDouble() ?? 0.02,
      hardness: (j['hardness'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpotMark &&
          source == other.source &&
          target == other.target &&
          radius == other.radius &&
          hardness == other.hardness);

  @override
  int get hashCode => Object.hash(source, target, radius, hardness);

  @override
  String toString() =>
      'SpotMark(source: $source, target: $target, radius: $radius, hardness: $hardness)';
}
