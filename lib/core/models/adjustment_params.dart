import 'package:e4pix/core/models/hsl_bands.dart';
import 'package:e4pix/core/models/crop_params.dart';
import 'package:e4pix/core/models/grain_params.dart';
import 'package:flutter/foundation.dart';

import 'local_adjustment.dart';
import 'rgb_curves.dart';
import 'tone_curve.dart';

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
  final double sharpenAmount; // 0-100，默认 0（不锐化）
  final double sharpenRadius; // 0.5-3.0 像素，默认 1.0
  final double sharpenMasking; // 0-100，默认 0（全图锐化）
  final double denoiseLuma; // 明度降噪 0-100，默认 0
  final double denoiseColor; // 颜色降噪 0-100，默认 0
  final double lutIntensity;
  final double lutIntensityB;
  final RgbCurves curves;
  final HslBands hsl;
  final GrainParams grain; // 胶片颗粒
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
    this.sharpenAmount = 0.0,
    this.sharpenRadius = 1.0,
    this.sharpenMasking = 0.0,
    this.denoiseLuma = 0.0,
    this.denoiseColor = 0.0,
    this.lutIntensity = 1.0,
    this.lutIntensityB = 1.0,
    this.curves = RgbCurves.identity,
    this.hsl = HslBands.neutral,
    this.grain = GrainParams.neutral,
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
    double? sharpenAmount,
    double? sharpenRadius,
    double? sharpenMasking,
    double? denoiseLuma,
    double? denoiseColor,
    double? lutIntensity,
    double? lutIntensityB,
    RgbCurves? curves,
    HslBands? hsl,
    GrainParams? grain,
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
    sharpenAmount: sharpenAmount ?? this.sharpenAmount,
    sharpenRadius: sharpenRadius ?? this.sharpenRadius,
    sharpenMasking: sharpenMasking ?? this.sharpenMasking,
    denoiseLuma: denoiseLuma ?? this.denoiseLuma,
    denoiseColor: denoiseColor ?? this.denoiseColor,
    lutIntensity: lutIntensity ?? this.lutIntensity,
    lutIntensityB: lutIntensityB ?? this.lutIntensityB,
    curves: curves ?? this.curves,
    hsl: hsl ?? this.hsl,
    grain: grain ?? this.grain,
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
          sharpenAmount == other.sharpenAmount &&
          sharpenRadius == other.sharpenRadius &&
          sharpenMasking == other.sharpenMasking &&
          denoiseLuma == other.denoiseLuma &&
          denoiseColor == other.denoiseColor &&
          lutIntensity == other.lutIntensity &&
          lutIntensityB == other.lutIntensityB &&
          curves == other.curves &&
          hsl == other.hsl &&
          grain == other.grain &&
          crop == other.crop &&
          listEquals(locals, other.locals);

  @override
  int get hashCode => Object.hashAll([
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
    sharpenAmount,
    sharpenRadius,
    sharpenMasking,
    denoiseLuma,
    denoiseColor,
    lutIntensity,
    lutIntensityB,
    curves,
    hsl,
    grain,
    crop,
    locals,
  ]);

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
    'sharpenAmount': sharpenAmount,
    'sharpenRadius': sharpenRadius,
    'sharpenMasking': sharpenMasking,
    'denoiseLuma': denoiseLuma,
    'denoiseColor': denoiseColor,
    'lutIntensity': lutIntensity,
    'lutIntensityB': lutIntensityB,
    'curves': curves.toJson(),
    'hsl': hsl.toJson(),
    'grain': grain.toJson(),
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
    sharpenAmount: (j['sharpenAmount'] as num?)?.toDouble() ?? 0.0,
    sharpenRadius: (j['sharpenRadius'] as num?)?.toDouble() ?? 1.0,
    sharpenMasking: (j['sharpenMasking'] as num?)?.toDouble() ?? 0.0,
    denoiseLuma: (j['denoiseLuma'] as num?)?.toDouble() ?? 0.0,
    denoiseColor: (j['denoiseColor'] as num?)?.toDouble() ?? 0.0,
    lutIntensity: (j['lutIntensity'] as num?)?.toDouble() ?? 1.0,
    lutIntensityB: (j['lutIntensityB'] as num?)?.toDouble() ?? 1.0,
    curves: j['curves'] != null
        ? RgbCurves.fromJson(j['curves'] as Map<String, dynamic>)
        : (j['toneCurve'] != null
              ? RgbCurves(
                  master: ToneCurve.fromJson(
                    j['toneCurve'] as Map<String, dynamic>,
                  ),
                )
              : RgbCurves.identity),
    hsl: j['hsl'] != null
        ? HslBands.fromJson(j['hsl'] as Map<String, dynamic>)
        : HslBands.neutral,
    grain: j['grain'] != null
        ? GrainParams.fromJson(j['grain'] as Map<String, dynamic>)
        : GrainParams.neutral,
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
