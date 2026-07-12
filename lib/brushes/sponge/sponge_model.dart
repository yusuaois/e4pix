import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../shared/stamp/stamp_mark.dart';

/// 海绵模式
enum SpongeMode {
  /// 饱和 — 增加色彩饱和度
  saturate,

  /// 去饱和 — 降低色彩饱和度
  desaturate,
}

/// 海绵工具笔触标记
///
/// 每个标记独立存储其渲染参数（模式/流量）
/// 落笔时冻结当前工具设置，后续切换不影响已有笔画
@immutable
class SpongeMark implements StampMark {
  /// 无源点偏移：效果类画笔从同位置处理
  @override
  Offset get source => target;

  /// 目标圆心（归一化 [0..1] 全图坐标）
  @override
  final Offset target;

  /// 半径（归一化，相对于源图宽度）
  @override
  final double radius;

  /// 硬度：1=硬边 step，0=柔边 smoothstep 全半径
  @override
  final double hardness;

  /// 饱和/去饱和模式（落笔时冻结）
  final SpongeMode mode;

  /// 流量强度 0..1（落笔时冻结）
  final double flow;

  @override
  final DateTime createdAt;

  const SpongeMark({
    required this.target,
    required this.createdAt,
    this.radius = 0.02,
    this.hardness = 1.0,
    this.mode = SpongeMode.saturate,
    this.flow = 0.5,
  });

  SpongeMark copyWith({
    Offset? target,
    double? radius,
    double? hardness,
    SpongeMode? mode,
    double? flow,
    DateTime? createdAt,
  }) {
    return SpongeMark(
      target: target ?? this.target,
      radius: radius ?? this.radius,
      hardness: hardness ?? this.hardness,
      mode: mode ?? this.mode,
      flow: flow ?? this.flow,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'targetX': target.dx,
    'targetY': target.dy,
    'radius': radius,
    'hardness': hardness,
    'mode': mode.name,
    'flow': flow,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory SpongeMark.fromJson(Map<String, dynamic> json) {
    final createdAt = StampMark.parseCreatedAt(json);
    return SpongeMark(
      target: Offset(
        (json['targetX'] as num?)?.toDouble() ?? 0.0,
        (json['targetY'] as num?)?.toDouble() ?? 0.0,
      ),
      radius: (json['radius'] as num?)?.toDouble() ?? 0.02,
      hardness: (json['hardness'] as num?)?.toDouble() ?? 1.0,
      mode: json['mode'] != null
          ? SpongeMode.values.byName(json['mode'] as String)
          : SpongeMode.saturate,
      flow: (json['flow'] as num?)?.toDouble() ?? 0.5,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpongeMark &&
      other.target == target &&
      other.radius == radius &&
      other.hardness == hardness &&
      other.mode == mode &&
      other.flow == flow &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(target, radius, hardness, mode, flow, createdAt);
}
