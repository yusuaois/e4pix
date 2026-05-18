import 'package:flutter/foundation.dart';

@immutable
class LocalParams {
  final double exposure;      // EV [-3, +3]
  final double contrast;      // [-100, +100]
  final double highlights;    // [-100, +100]
  final double shadows;
  final double whites;
  final double blacks;
  final int temperatureShift; // K 偏移 [-3000, +3000]
  final double tint;          // [-100, +100]
  final double saturation;    // [-100, +100]
  final double vibrance;      // [-100, +100]

  const LocalParams({
    this.exposure = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.temperatureShift = 0,
    this.tint = 0.0,
    this.saturation = 0.0,
    this.vibrance = 0.0,
  });

  static const neutral = LocalParams();

  bool get isNeutral =>
      exposure == 0 &&
      contrast == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      whites == 0 &&
      blacks == 0 &&
      temperatureShift == 0 &&
      tint == 0 &&
      saturation == 0 &&
      vibrance == 0;

  LocalParams copyWith({
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    int? temperatureShift,
    double? tint,
    double? saturation,
    double? vibrance,
  }) =>
      LocalParams(
        exposure: exposure ?? this.exposure,
        contrast: contrast ?? this.contrast,
        highlights: highlights ?? this.highlights,
        shadows: shadows ?? this.shadows,
        whites: whites ?? this.whites,
        blacks: blacks ?? this.blacks,
        temperatureShift: temperatureShift ?? this.temperatureShift,
        tint: tint ?? this.tint,
        saturation: saturation ?? this.saturation,
        vibrance: vibrance ?? this.vibrance,
      );

  Map<String, dynamic> toJson() => {
        'exposure': exposure,
        'contrast': contrast,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'temperatureShift': temperatureShift,
        'tint': tint,
        'saturation': saturation,
        'vibrance': vibrance,
      };

  factory LocalParams.fromJson(Map<String, dynamic> j) => LocalParams(
        exposure: (j['exposure'] as num?)?.toDouble() ?? 0.0,
        contrast: (j['contrast'] as num?)?.toDouble() ?? 0.0,
        highlights: (j['highlights'] as num?)?.toDouble() ?? 0.0,
        shadows: (j['shadows'] as num?)?.toDouble() ?? 0.0,
        whites: (j['whites'] as num?)?.toDouble() ?? 0.0,
        blacks: (j['blacks'] as num?)?.toDouble() ?? 0.0,
        temperatureShift: (j['temperatureShift'] as num?)?.toInt() ?? 0,
        tint: (j['tint'] as num?)?.toDouble() ?? 0.0,
        saturation: (j['saturation'] as num?)?.toDouble() ?? 0.0,
        vibrance: (j['vibrance'] as num?)?.toDouble() ?? 0.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalParams &&
          exposure == other.exposure &&
          contrast == other.contrast &&
          highlights == other.highlights &&
          shadows == other.shadows &&
          whites == other.whites &&
          blacks == other.blacks &&
          temperatureShift == other.temperatureShift &&
          tint == other.tint &&
          saturation == other.saturation &&
          vibrance == other.vibrance);

  @override
  int get hashCode => Object.hash(
        exposure, contrast, highlights, shadows, whites, blacks,
        temperatureShift, tint, saturation, vibrance,
      );
}