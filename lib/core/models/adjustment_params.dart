import 'package:e4pix/core/models/hsl_bands.dart';
import 'package:e4pix/core/models/crop_params.dart';
import 'package:flutter/foundation.dart';

import 'local_adjustment.dart';

@immutable
class AdjustmentParams {
  final double exposure; // EV, [-5, +5]
  final int temperature; // K, 2000-12000
  final double tint; // [-100, +100]
  final double contrast; // [-100, +100]
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;
  final double saturation;
  final double vibrance;
  final double lutIntensity;
  final HslBands hsl;
  final CropParams crop;
  final List<LocalAdjustment> locals;

  const AdjustmentParams({
    this.exposure = 0.0,
    this.temperature = 5500,
    this.tint = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.saturation = 0.0,
    this.vibrance = 0.0,
    this.lutIntensity = 1.0,
    this.hsl = HslBands.neutral,
    this.crop = CropParams.identity,
    this.locals = const [],
  });

  static const neutral = AdjustmentParams();

  AdjustmentParams copyWith({
    double? exposure,
    int? temperature,
    double? tint,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? saturation,
    double? vibrance,
    double? lutIntensity,
    HslBands? hsl,
    CropParams? crop,
    List<LocalAdjustment>? locals,
  }) => AdjustmentParams(
    exposure: exposure ?? this.exposure,
    temperature: temperature ?? this.temperature,
    tint: tint ?? this.tint,
    contrast: contrast ?? this.contrast,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    whites: whites ?? this.whites,
    blacks: blacks ?? this.blacks,
    saturation: saturation ?? this.saturation,
    vibrance: vibrance ?? this.vibrance,
    lutIntensity: lutIntensity ?? this.lutIntensity,
    hsl: hsl ?? this.hsl,
    crop: crop ?? this.crop,
    locals: locals ?? this.locals,
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
          lutIntensity == other.lutIntensity &&
          hsl == other.hsl &&
          crop == other.crop &&
          listEquals(locals, other.locals);

  @override
  int get hashCode => Object.hash(
    exposure,
    temperature,
    tint,
    contrast,
    highlights,
    shadows,
    whites,
    blacks,
    saturation,
    vibrance,
    lutIntensity,
    hsl,
    crop,
    locals,
  );

  Map<String, dynamic> toJson() => {
    'exposure': exposure,
    'temperature': temperature,
    'tint': tint,
    'contrast': contrast,
    'highlights': highlights,
    'shadows': shadows,
    'whites': whites,
    'blacks': blacks,
    'saturation': saturation,
    'vibrance': vibrance,
    'lutIntensity': lutIntensity,
    'hsl': hsl.toJson(),
    'crop': crop.toJson(),
    'locals': locals.map((e) => e.toJson()).toList(),
  };

  factory AdjustmentParams.fromJson(Map<String, dynamic> j) => AdjustmentParams(
    exposure: (j['exposure'] as num?)?.toDouble() ?? 0.0,
    temperature: (j['temperature'] as num?)?.toInt() ?? 5500,
    tint: (j['tint'] as num?)?.toDouble() ?? 0.0,
    contrast: (j['contrast'] as num?)?.toDouble() ?? 0.0,
    highlights: (j['highlights'] as num?)?.toDouble() ?? 0.0,
    shadows: (j['shadows'] as num?)?.toDouble() ?? 0.0,
    whites: (j['whites'] as num?)?.toDouble() ?? 0.0,
    blacks: (j['blacks'] as num?)?.toDouble() ?? 0.0,
    saturation: (j['saturation'] as num?)?.toDouble() ?? 0.0,
    vibrance: (j['vibrance'] as num?)?.toDouble() ?? 0.0,
    lutIntensity: (j['lutIntensity'] as num?)?.toDouble() ?? 1.0,
    hsl: j['hsl'] != null
        ? HslBands.fromJson(j['hsl'] as Map<String, dynamic>)
        : HslBands.neutral,
    crop: j['crop'] != null
        ? CropParams.fromJson(j['crop'] as Map<String, dynamic>)
        : CropParams.identity,
    locals:
        (j['locals'] as List?)
            ?.map((e) => LocalAdjustment.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
