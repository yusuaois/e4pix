import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/models/adjustment_params.dart';
import 'shared.dart';

class LightSection extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const LightSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Light'),
        DevelopSliderTile(
          label: tr("exposure"),
          value: p.exposure,
          min: -5,
          max: 5,
          onChanged: (v) => onChanged(p.copyWith(exposure: v)),
          suffix: ' EV',
          precision: 2,
        ),
        DevelopSliderTile(
          label: tr("contrast"),
          value: p.contrast,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(contrast: v)),
        ),
        DevelopSliderTile(
          label: tr("highlight"),
          value: p.highlights,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(highlights: v)),
        ),
        DevelopSliderTile(
          label: tr("shadow"),
          value: p.shadows,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(shadows: v)),
        ),
        DevelopSliderTile(
          label: tr("white"),
          value: p.whites,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(whites: v)),
        ),
        DevelopSliderTile(
          label: tr("black"),
          value: p.blacks,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(blacks: v)),
        ),
      ],
    );
  }
}
