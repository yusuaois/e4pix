import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../shared/stamp/stamp_mark.dart';

/// 历史记录画笔标记
///
/// 从 History 面板选中的冻结快照恢复像素到当前画面
/// 只需 [target] 位置（无 source 偏移），同一位置采样快照像素
@immutable
class HistoryMark implements StampMark {
  @override
  final Offset target;

  /// History Brush 无偏移：source 始终等于 target（从快照同位置采样）
  @override
  Offset get source => target;

  @override
  final double radius;

  @override
  final double hardness;

  @override
  final DateTime createdAt;

  const HistoryMark({
    required this.target,
    required this.createdAt,
    this.radius = 0.02,
    this.hardness = 1.0,
  });

  @override
  Map<String, dynamic> toJson() => {
    'target': [target.dx, target.dy],
    'radius': radius,
    'hardness': hardness,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory HistoryMark.fromJson(Map<String, dynamic> j) {
    final tgt = j['target'] as List?;
    final createdAt = StampMark.parseCreatedAt(j);
    return HistoryMark(
      target: tgt != null && tgt.length >= 2
          ? Offset((tgt[0] as num).toDouble(), (tgt[1] as num).toDouble())
          : Offset.zero,
      radius: (j['radius'] as num?)?.toDouble() ?? 0.02,
      hardness: (j['hardness'] as num?)?.toDouble() ?? 1.0,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryMark &&
          target == other.target &&
          radius == other.radius &&
          hardness == other.hardness &&
          createdAt == other.createdAt);

  @override
  int get hashCode => Object.hash(target, radius, hardness, createdAt);

  @override
  String toString() =>
      'HistoryMark(target: $target, radius: $radius, hardness: $hardness, createdAt: $createdAt)';
}
