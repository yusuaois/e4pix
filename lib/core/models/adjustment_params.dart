import 'package:e4pix/core/models/hsl_bands.dart';
import 'package:flutter/foundation.dart';

@immutable
class AdjustmentParams {
  final double exposure;     // EV, [-5, +5]
  final int    temperature;  // K, 2000-12000
  final double tint;         // [-100, +100]
  final double contrast;     // [-100, +100]
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double saturation;
  final double vibrance;
  final HslBands hsl;

  const AdjustmentParams({
    this.exposure   = 0.0,
    this.temperature = 5500,
    this.tint       = 0.0,
    this.contrast   = 0.0,
    this.highlights = 0.0,
    this.shadows    = 0.0,
    this.whites     = 0.0,
    this.blacks     = 0.0,
    this.saturation = 0.0,
    this.vibrance   = 0.0,
    this.hsl        = HslBands.neutral,
  });

  static const neutral = AdjustmentParams();

  AdjustmentParams copyWith({
    double? exposure, int? temperature, double? tint,
    double? contrast, double? highlights, double? shadows,
    double? whites, double? blacks,
    double? saturation, double? vibrance,
    HslBands? hsl,
  }) =>
      AdjustmentParams(
        exposure:   exposure   ?? this.exposure,
        temperature: temperature ?? this.temperature,
        tint:       tint       ?? this.tint,
        contrast:   contrast   ?? this.contrast,
        highlights: highlights ?? this.highlights,
        shadows:    shadows    ?? this.shadows,
        whites:     whites     ?? this.whites,
        blacks:     blacks     ?? this.blacks,
        saturation: saturation ?? this.saturation,
        vibrance:   vibrance   ?? this.vibrance,
        hsl:          hsl          ?? this.hsl,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdjustmentParams &&
          exposure == other.exposure &&
          temperature == other.temperature &&
          tint == other.tint &&
          contrast == other.contrast &&
          highlights == other.highlights &&
          shadows == other.shadows &&
          whites == other.whites &&
          blacks == other.blacks &&
          saturation == other.saturation &&
          vibrance == other.vibrance &&
          hsl == other.hsl;

  @override
  int get hashCode => Object.hash(
        exposure, temperature, tint, contrast,
        highlights, shadows, whites, blacks,
        saturation, vibrance, hsl,
      );
}