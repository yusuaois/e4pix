import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/local_adjustment.dart';
import '../../../../core/models/mask_shape.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../state/providers.dart';
import '../local_section.dart';

class LocalShapeControls extends ConsumerWidget {
  final LocalAdjustment local;
  const LocalShapeControls({super.key, required this.local});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = local.mask;
    if (shape is! RadialGradientMask) return const SizedBox.shrink();

    final actions = LocalAdjustmentActions(ref);

    return Column(
      children: [
        MiniSlider(
          label: tr("rotation"),
          value: shape.rotation,
          min: -3.14159,
          max: 3.14159,
          formatter: (v) => '${(v * 180 / 3.14159).toStringAsFixed(0)}°',
          onChanged: (v) => actions.updateLocal(
            local.id,
            (l) => l.copyWith(mask: shape.copyWith(rotation: v)),
          ),
        ),
        MiniSlider(
          label: tr("feather"),
          value: shape.feather,
          min: 0,
          max: 1,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) => actions.updateLocal(
            local.id,
            (l) => l.copyWith(mask: shape.copyWith(feather: v)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(tr("invert"), style: AppTypography.labelMedium),
              ),
              Switch(
                value: shape.inverted,
                onChanged: (v) => actions.updateLocal(
                  local.id,
                  (l) => l.copyWith(mask: shape.copyWith(inverted: v)),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
