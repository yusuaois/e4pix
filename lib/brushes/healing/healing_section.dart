import "healing_state.dart";
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

import "../../widgets/develop/sections/shared.dart";

/// Healing Brush section.
///
/// - Activation pill chip
/// - Sampling button (mobile — replaces hold key)
/// - Radius / Hardness sliders
/// - Clear All button
class HealingSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const HealingSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(healingStateProvider);
    final notifier = ref.read(healingStateProvider.notifier);
    final isActive = state.mode == HealingMode.active;
    final isSampling = state.samplingButtonOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'healing'),

        // ── Activation + Sampling ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              PillChip(
                icon: Icons.healing,
                label: tr('healingTitle'),
                isActive: isActive,
                onTap: () => notifier.setMode(
                  isActive ? HealingMode.inactive : HealingMode.active,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                PillChip(
                  icon: Icons.colorize,
                  label: tr('healingSample'),
                  isActive: isSampling,
                  onTap: notifier.toggleSamplingButton,
                ),
              ],
              const Spacer(),
            ],
          ),
        ),

        // ── Hint + sliders (active only) ──
        if (isActive) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              state.cloneSource != null
                  ? tr('healingSourceSet')
                  : tr('healingAltHint'),
              style: AppTypography.labelSmall.copyWith(
                color: state.cloneSource != null
                    ? AppColors.semanticSuccess
                    : AppColors.disabledText,
              ),
            ),
          ),
          const SizedBox(height: 4),
          DevelopSliderTile(
            label: tr('healingRadius'),
            value: state.brushRadius * 1000,
            min: 2,
            max: 100,
            fractionDigits: 0,
            suffix: '‰',
            onChanged: (v) => notifier.setBrushRadius(v / 1000),
          ),
          DevelopSliderTile(
            label: tr('healingHardness'),
            value: state.brushHardness * 100,
            min: 0,
            max: 100,
            fractionDigits: 0,
            suffix: '%',
            onChanged: (v) => notifier.setBrushHardness(v / 100),
          ),
        ],

        // ── Clear All ──
        if (isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: notifier.clearAll,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(tr('ClearAll')),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.semanticError,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
