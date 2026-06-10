import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/local_adjustment.dart';
import '../../../../core/models/local_params.dart';
import '../../../../state/providers.dart';
import '../local_section.dart';

class LocalParamsControls extends ConsumerWidget {
  final LocalAdjustment local;
  const LocalParamsControls({super.key, required this.local});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = local.params;
    final actions = LocalAdjustmentActions(ref);

    void update(LocalParams Function(LocalParams) f) {
      actions.updateLocal(local.id, (l) => l.copyWith(params: f(l.params)));
    }

    return Column(
      children: [
        MiniSlider(
          label: tr("exposure"),
          value: p.exposure,
          min: -3,
          max: 3,
          formatter: (v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(2)}',
          onChanged: (v) => update((q) => q.copyWith(exposure: v)),
        ),
        MiniSlider(
          label: tr("contrast"),
          value: p.contrast,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(contrast: v)),
        ),
        MiniSlider(
          label: tr("highlight"),
          value: p.highlights,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(highlights: v)),
        ),
        MiniSlider(
          label: tr("shadow"),
          value: p.shadows,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(shadows: v)),
        ),
        MiniSlider(
          label: tr("white"),
          value: p.whites,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(whites: v)),
        ),
        MiniSlider(
          label: tr("black"),
          value: p.blacks,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(blacks: v)),
        ),
        MiniSlider(
          label: tr("whiteBalance"),
          value: p.temperatureShift.toDouble(),
          min: -3000,
          max: 3000,
          formatter: (v) => '${v >= 0 ? "+" : ""}${v.round()}',
          onChanged: (v) =>
              update((q) => q.copyWith(temperatureShift: v.round())),
        ),
        MiniSlider(
          label: tr("tint"),
          value: p.tint,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(tint: v)),
        ),
        MiniSlider(
          label: tr("saturation"),
          value: p.saturation,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(saturation: v)),
        ),
        MiniSlider(
          label: tr("vibrance"),
          value: p.vibrance,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(vibrance: v)),
        ),
      ],
    );
  }
}
