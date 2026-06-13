import 'package:flutter/foundation.dart';

/// 镜头校正参数
///
/// 包含色差(CA)、畸变(Distortion)、暗角(Vignetting)三个子模块
@immutable
class LensCorrectionParams {
  /// 色差校正开关
  final bool enabled;

  /// CA 红通道缩放系数（LibRaw aber[0]）
  final double caRed;

  /// CA 蓝通道缩放系数（LibRaw aber[2]）
  final double caBlue;

  /// 畸变校正开关
  final bool distortionEnabled;

  /// 畸变多项式系数 k1..k5（Lensfun poly5 模型）
  final double distortionK1;
  final double distortionK2;
  final double distortionK3;
  final double distortionK4;
  final double distortionK5;

  /// 光心偏移（归一化，默认 0.5 即正中心）
  final double opticalCenterX;
  final double opticalCenterY;

  /// 暗角校正开关
  final bool vignettingEnabled;

  /// 暗角多项式系数 k1..k3（Lensfun 模型）
  final double vignettingK1;
  final double vignettingK2;
  final double vignettingK3;

  const LensCorrectionParams({
    this.enabled = false,
    this.caRed = 1.0,
    this.caBlue = 1.0,
    this.distortionEnabled = false,
    this.distortionK1 = 0.0,
    this.distortionK2 = 0.0,
    this.distortionK3 = 0.0,
    this.distortionK4 = 0.0,
    this.distortionK5 = 0.0,
    this.opticalCenterX = 0.5,
    this.opticalCenterY = 0.5,
    this.vignettingEnabled = false,
    this.vignettingK1 = 0.0,
    this.vignettingK2 = 0.0,
    this.vignettingK3 = 0.0,
  });

  static const neutral = LensCorrectionParams();

  bool get isNeutral =>
      !enabled &&
      caRed == 1.0 &&
      caBlue == 1.0 &&
      !distortionEnabled &&
      distortionK1 == 0.0 &&
      distortionK2 == 0.0 &&
      distortionK3 == 0.0 &&
      distortionK4 == 0.0 &&
      distortionK5 == 0.0 &&
      !vignettingEnabled &&
      vignettingK1 == 0.0 &&
      vignettingK2 == 0.0 &&
      vignettingK3 == 0.0;

  bool get isCaActive => enabled && (caRed != 0.0 || caBlue != 0.0);
  bool get isDistortionActive => distortionEnabled;
  bool get isVignettingActive => vignettingEnabled;

  LensCorrectionParams copyWith({
    bool? enabled,
    double? caRed,
    double? caBlue,
    bool? distortionEnabled,
    double? distortionK1,
    double? distortionK2,
    double? distortionK3,
    double? distortionK4,
    double? distortionK5,
    double? opticalCenterX,
    double? opticalCenterY,
    bool? vignettingEnabled,
    double? vignettingK1,
    double? vignettingK2,
    double? vignettingK3,
  }) => LensCorrectionParams(
    enabled: enabled ?? this.enabled,
    caRed: caRed ?? this.caRed,
    caBlue: caBlue ?? this.caBlue,
    distortionEnabled: distortionEnabled ?? this.distortionEnabled,
    distortionK1: distortionK1 ?? this.distortionK1,
    distortionK2: distortionK2 ?? this.distortionK2,
    distortionK3: distortionK3 ?? this.distortionK3,
    distortionK4: distortionK4 ?? this.distortionK4,
    distortionK5: distortionK5 ?? this.distortionK5,
    opticalCenterX: opticalCenterX ?? this.opticalCenterX,
    opticalCenterY: opticalCenterY ?? this.opticalCenterY,
    vignettingEnabled: vignettingEnabled ?? this.vignettingEnabled,
    vignettingK1: vignettingK1 ?? this.vignettingK1,
    vignettingK2: vignettingK2 ?? this.vignettingK2,
    vignettingK3: vignettingK3 ?? this.vignettingK3,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LensCorrectionParams &&
          enabled == other.enabled &&
          caRed == other.caRed &&
          caBlue == other.caBlue &&
          distortionEnabled == other.distortionEnabled &&
          distortionK1 == other.distortionK1 &&
          distortionK2 == other.distortionK2 &&
          distortionK3 == other.distortionK3 &&
          distortionK4 == other.distortionK4 &&
          distortionK5 == other.distortionK5 &&
          opticalCenterX == other.opticalCenterX &&
          opticalCenterY == other.opticalCenterY &&
          vignettingEnabled == other.vignettingEnabled &&
          vignettingK1 == other.vignettingK1 &&
          vignettingK2 == other.vignettingK2 &&
          vignettingK3 == other.vignettingK3;

  @override
  int get hashCode => Object.hashAll([
    enabled,
    caRed,
    caBlue,
    distortionEnabled,
    distortionK1,
    distortionK2,
    distortionK3,
    distortionK4,
    distortionK5,
    opticalCenterX,
    opticalCenterY,
    vignettingEnabled,
    vignettingK1,
    vignettingK2,
    vignettingK3,
  ]);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'caRed': caRed,
    'caBlue': caBlue,
    'distortionEnabled': distortionEnabled,
    'distortionK1': distortionK1,
    'distortionK2': distortionK2,
    'distortionK3': distortionK3,
    'distortionK4': distortionK4,
    'distortionK5': distortionK5,
    'opticalCenterX': opticalCenterX,
    'opticalCenterY': opticalCenterY,
    'vignettingEnabled': vignettingEnabled,
    'vignettingK1': vignettingK1,
    'vignettingK2': vignettingK2,
    'vignettingK3': vignettingK3,
  };

  factory LensCorrectionParams.fromJson(Map<String, dynamic> j) {
    double d(String k, double fallback) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    return LensCorrectionParams(
      enabled: j['enabled'] as bool? ?? false,
      caRed: d('caRed', 1.0),
      caBlue: d('caBlue', 1.0),
      distortionEnabled: j['distortionEnabled'] as bool? ?? false,
      distortionK1: d('distortionK1', 0.0),
      distortionK2: d('distortionK2', 0.0),
      distortionK3: d('distortionK3', 0.0),
      distortionK4: d('distortionK4', 0.0),
      distortionK5: d('distortionK5', 0.0),
      opticalCenterX: d('opticalCenterX', 0.5),
      opticalCenterY: d('opticalCenterY', 0.5),
      vignettingEnabled: j['vignettingEnabled'] as bool? ?? false,
      vignettingK1: d('vignettingK1', 0.0),
      vignettingK2: d('vignettingK2', 0.0),
      vignettingK3: d('vignettingK3', 0.0),
    );
  }
}
