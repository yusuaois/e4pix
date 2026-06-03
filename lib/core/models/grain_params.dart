import 'package:flutter/foundation.dart';

/// 胶片颗粒参数（移植自 Lut2Photo 的 FilmGrainConfig）
///
/// 强弱由 [amount] 控制（0 = 关闭）；[size] 控制颗粒团块大小
@immutable
class GrainParams {
  /// 全局强度 [0, 100]，0 = 关闭
  final double amount;

  /// 颗粒尺寸 [0.1, 10]，团块大小（不再影响强度）
  final double size;

  /// 影调阈值（0-255 亮度值）
  final double shadowThreshold; // 阴影/中间调分界，默认 85
  final double highlightThreshold; // 中间调/高光分界，默认 170

  /// 影调强度比（中间调基准 1.0）
  final double shadowStrength; // [0.2, 1.0]
  final double highlightStrength; // [0.1, 0.8]

  /// 影调尺寸比（中间调基准 1.0）
  final double shadowSize; // [1.0, 2.0]
  final double highlightSize; // [0.3, 1.0]

  /// 通道差异（绿通道基准 1.0）
  final double redRatio; // [0.5, 1.5]
  final double blueRatio; // [0.8, 1.5]
  final double correlation; // 通道相关性 [0.8, 0.95]，越高越单色
  final double colorPreservation; // 色彩保护 [0.9, 1.0]

  const GrainParams({
    this.amount = 0.0,
    this.size = 1.0,
    this.shadowThreshold = 85.0,
    this.highlightThreshold = 170.0,
    this.shadowStrength = 0.6,
    this.highlightStrength = 0.3,
    this.shadowSize = 1.5,
    this.highlightSize = 0.6,
    this.redRatio = 0.9,
    this.blueRatio = 1.2,
    this.correlation = 0.9,
    this.colorPreservation = 0.95,
  });

  static const neutral = GrainParams();

  bool get isNeutral => amount == 0.0;

  GrainParams copyWith({
    double? amount,
    double? size,
    double? shadowThreshold,
    double? highlightThreshold,
    double? shadowStrength,
    double? highlightStrength,
    double? shadowSize,
    double? highlightSize,
    double? redRatio,
    double? blueRatio,
    double? correlation,
    double? colorPreservation,
  }) => GrainParams(
    amount: amount ?? this.amount,
    size: size ?? this.size,
    shadowThreshold: shadowThreshold ?? this.shadowThreshold,
    highlightThreshold: highlightThreshold ?? this.highlightThreshold,
    shadowStrength: shadowStrength ?? this.shadowStrength,
    highlightStrength: highlightStrength ?? this.highlightStrength,
    shadowSize: shadowSize ?? this.shadowSize,
    highlightSize: highlightSize ?? this.highlightSize,
    redRatio: redRatio ?? this.redRatio,
    blueRatio: blueRatio ?? this.blueRatio,
    correlation: correlation ?? this.correlation,
    colorPreservation: colorPreservation ?? this.colorPreservation,
  );

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'size': size,
    'shadowThreshold': shadowThreshold,
    'highlightThreshold': highlightThreshold,
    'shadowStrength': shadowStrength,
    'highlightStrength': highlightStrength,
    'shadowSize': shadowSize,
    'highlightSize': highlightSize,
    'redRatio': redRatio,
    'blueRatio': blueRatio,
    'correlation': correlation,
    'colorPreservation': colorPreservation,
  };

  factory GrainParams.fromJson(Map<String, dynamic> j) {
    double d(String k, double fallback) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    return GrainParams(
      amount: d('amount', 0.0),
      size: d('size', 1.0),
      shadowThreshold: d('shadowThreshold', 85.0),
      highlightThreshold: d('highlightThreshold', 170.0),
      shadowStrength: d('shadowStrength', 0.6),
      highlightStrength: d('highlightStrength', 0.3),
      shadowSize: d('shadowSize', 1.5),
      highlightSize: d('highlightSize', 0.6),
      redRatio: d('redRatio', 0.9),
      blueRatio: d('blueRatio', 1.2),
      correlation: d('correlation', 0.9),
      colorPreservation: d('colorPreservation', 0.95),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GrainParams &&
          amount == other.amount &&
          size == other.size &&
          shadowThreshold == other.shadowThreshold &&
          highlightThreshold == other.highlightThreshold &&
          shadowStrength == other.shadowStrength &&
          highlightStrength == other.highlightStrength &&
          shadowSize == other.shadowSize &&
          highlightSize == other.highlightSize &&
          redRatio == other.redRatio &&
          blueRatio == other.blueRatio &&
          correlation == other.correlation &&
          colorPreservation == other.colorPreservation);

  @override
  int get hashCode => Object.hash(
    amount,
    size,
    shadowThreshold,
    highlightThreshold,
    shadowStrength,
    highlightStrength,
    shadowSize,
    highlightSize,
    redRatio,
    blueRatio,
    correlation,
    colorPreservation,
  );
}
