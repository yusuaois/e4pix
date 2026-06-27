import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 污点修复标记（仿制图章）
///
/// 用户在预览图上标记一个污点区域（[target]），并指定采样源区域（[source]）。
/// 渲染时将 [source] 处的像素克隆到 [target] 处，以 [radius] 为半径带柔边混合。
/// 所有坐标均为归一化 [0..1]，相对于源图（非裁剪后）坐标系。
@immutable
class SpotMark {
  /// 采样源位置（归一化 [0..1]，源图坐标系）
  final Offset source;

  /// 修复目标位置（归一化 [0..1]，源图坐标系）
  final Offset target;

  /// 修复半径（归一化，相对源图宽度），默认 0.02 = 源图宽度的 2%
  final double radius;

  const SpotMark({
    required this.source,
    required this.target,
    this.radius = 0.02,
  });

  SpotMark copyWith({
    Offset? source,
    Offset? target,
    double? radius,
  }) => SpotMark(
    source: source ?? this.source,
    target: target ?? this.target,
    radius: radius ?? this.radius,
  );

  Map<String, dynamic> toJson() => {
    'source': [source.dx, source.dy],
    'target': [target.dx, target.dy],
    'radius': radius,
  };

  factory SpotMark.fromJson(Map<String, dynamic> j) {
    final src = j['source'] as List?;
    final tgt = j['target'] as List?;
    return SpotMark(
      source: src != null && src.length >= 2
          ? Offset(
              (src[0] as num).toDouble(),
              (src[1] as num).toDouble(),
            )
          : Offset.zero,
      target: tgt != null && tgt.length >= 2
          ? Offset(
              (tgt[0] as num).toDouble(),
              (tgt[1] as num).toDouble(),
            )
          : Offset.zero,
      radius: (j['radius'] as num?)?.toDouble() ?? 0.02,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpotMark &&
          source == other.source &&
          target == other.target &&
          radius == other.radius);

  @override
  int get hashCode => Object.hash(source, target, radius);

  @override
  String toString() =>
      'SpotMark(source: $source, target: $target, radius: $radius)';
}
