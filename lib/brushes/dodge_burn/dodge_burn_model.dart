import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Dodge/Burn 模式
enum DodgeBurnMode {
  /// 减淡 — 提亮像素
  dodge,

  /// 加深 — 压暗像素
  burn,
}

/// 色调范围（对齐 Photoshop）
enum DodgeBurnRange {
  /// 阴影 — 只影响暗部
  shadows,

  /// 中间调 — 影响中间亮度区域
  midtones,

  /// 高光 — 只影响亮部
  highlights,
}

/// Dodge/Burn 笔触标记
///
/// 每个标记独立存储其渲染参数（模式/范围/曝光）。
/// 落笔时冻结当前工具设置，后续切换不影响已有笔画。
@immutable
class DodgeBurnMark {
  /// 目标圆心（归一化 [0..1] 全图坐标）
  final Offset target;

  /// 半径（归一化，相对于源图宽度）
  final double radius;

  /// 硬度：1=硬边 step，0=软边 smoothstep 全半径
  final double hardness;

  /// 减淡/加深模式（落笔时冻结）
  final DodgeBurnMode mode;

  /// 色调范围（落笔时冻结）
  final DodgeBurnRange range;

  /// 曝光强度 0..1（落笔时冻结）
  final double exposure;

  const DodgeBurnMark({
    required this.target,
    this.radius = 0.02,
    this.hardness = 1.0,
    this.mode = DodgeBurnMode.dodge,
    this.range = DodgeBurnRange.midtones,
    this.exposure = 0.5,
  });

  DodgeBurnMark copyWith({
    Offset? target,
    double? radius,
    double? hardness,
    DodgeBurnMode? mode,
    DodgeBurnRange? range,
    double? exposure,
  }) {
    return DodgeBurnMark(
      target: target ?? this.target,
      radius: radius ?? this.radius,
      hardness: hardness ?? this.hardness,
      mode: mode ?? this.mode,
      range: range ?? this.range,
      exposure: exposure ?? this.exposure,
    );
  }

  Map<String, dynamic> toJson() => {
    'targetX': target.dx,
    'targetY': target.dy,
    'radius': radius,
    'hardness': hardness,
    'mode': mode.name,
    'range': range.name,
    'exposure': exposure,
  };

  factory DodgeBurnMark.fromJson(Map<String, dynamic> json) {
    return DodgeBurnMark(
      target: Offset(
        (json['targetX'] as num).toDouble(),
        (json['targetY'] as num).toDouble(),
      ),
      radius: (json['radius'] as num).toDouble(),
      hardness: (json['hardness'] as num).toDouble(),
      mode: json['mode'] != null
          ? DodgeBurnMode.values.byName(json['mode'] as String)
          : DodgeBurnMode.dodge,
      range: json['range'] != null
          ? DodgeBurnRange.values.byName(json['range'] as String)
          : DodgeBurnRange.midtones,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.5,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DodgeBurnMark &&
      other.target == target &&
      other.radius == radius &&
      other.hardness == hardness &&
      other.mode == mode &&
      other.range == range &&
      other.exposure == exposure;

  @override
  int get hashCode =>
      Object.hash(target, radius, hardness, mode, range, exposure);
}
