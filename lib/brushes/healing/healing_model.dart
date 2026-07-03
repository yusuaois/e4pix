import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Healing brush mark.
///
/// Unlike SpotMark (clone stamp — direct pixel copy), the healing brush
/// uses frequency-separation blending: source texture detail is transferred
/// while target color/luminance context is preserved.
///
/// All coordinates are normalized [0..1], relative to the source image
/// (pre-crop) coordinate system.
@immutable
class HealingMark {
  /// Sample source position (normalized [0..1], source-image coords)
  final Offset source;

  /// Repair target position (normalized [0..1], source-image coords)
  final Offset target;

  /// Brush radius (normalized, relative to source image width).
  /// Default 0.02 = 2 % of source width.
  final double radius;

  /// Edge hardness 0..1, 1 = hard edge, 0 = soft edge.
  final double hardness;

  const HealingMark({
    required this.source,
    required this.target,
    this.radius = 0.02,
    this.hardness = 1.0,
  });

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
