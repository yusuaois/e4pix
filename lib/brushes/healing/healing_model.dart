import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../shared/stamp_mark.dart';

/// 修复画笔标记
///
/// 与图章（直接像素复制）不同，修复画笔使用频域分离混合：
/// 转移源纹理细节，同时保留目标颜色/亮度上下文
///
/// 所有坐标归一化 [0..1]，相对源图（裁剪前）坐标系
@immutable
class HealingMark implements StampMark {
  /// 采样源位置（归一化 [0..1]，源图坐标系）
  @override
  final Offset source;

  /// 修复目标位置（归一化 [0..1]，源图坐标系）
  @override
  final Offset target;

  /// 笔刷半径（归一化，相对源图宽度），默认 0.02 = 源图宽度的 2%
  @override
  final double radius;

  /// 边缘硬度 0..1，1=硬边，0=柔边
  @override
  final double hardness;

  const HealingMark({
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

  factory HealingMark.fromJson(Map<String, dynamic> j) {
    final src = j['source'] as List?;
    final tgt = j['target'] as List?;
    return HealingMark(
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
      (other is HealingMark &&
          source == other.source &&
          target == other.target &&
          radius == other.radius &&
          hardness == other.hardness);

  @override
  int get hashCode => Object.hash(source, target, radius, hardness);

  @override
  String toString() =>
      'HealingMark(source: $source, target: $target, radius: $radius, hardness: $hardness)';
}
