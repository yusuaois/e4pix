import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/adjustment_params.dart';
import '../shared.dart';

class WhiteBalanceColorSection extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const WhiteBalanceColorSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = params;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel(title: 'White Balance'),
          DevelopSliderTile(
            label: tr("whiteBalance"),
            value: p.temperature.toDouble(),
            min: 2000,
            max: 12000,
            onChanged: (v) => onChanged(p.copyWith(temperature: v.round())),
            suffix: ' K',
          ),
          DevelopSliderTile(
            label: tr("tint"),
            value: p.tint,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(p.copyWith(tint: v)),
          ),
          const SectionLabel(title: 'Color'),
          DevelopSliderTile(
            label: tr("saturation"),
            value: p.saturation,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(p.copyWith(saturation: v)),
          ),
          DevelopSliderTile(
            label: tr("vibrance"),
            value: p.vibrance,
            min: -100,
            max: 100,
            onChanged: (v) => onChanged(p.copyWith(vibrance: v)),
          ),
        ],
      ),
    );
  }
}
