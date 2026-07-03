import "clone_stamp_state.dart";
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

import "../../widgets/develop/sections/shared.dart";

/// 污点修复 Section
///
/// - 标题 "Spot Removal"
/// - 激活切换按钮
/// - 取样按钮（手机用，替代 hold 键）
/// - 半径滑块
/// - 硬度滑块
/// - 清除全部按钮
class SpotRemoveSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const SpotRemoveSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spotRemoveStateProvider);
    final notifier = ref.read(spotRemoveStateProvider.notifier);
    final isActive = state.mode == SpotRemoveMode.active;
    final isSampling = state.samplingButtonOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'spotRemove'),

        // ── 激活切换 + 取样按钮 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              // 激活按钮
              _PillChip(
                icon: Icons.healing,
                label: tr('spotRemoveTitle'),
                isActive: isActive,
                onTap: () => notifier.setMode(
                  isActive ? SpotRemoveMode.inactive : SpotRemoveMode.active,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                // 取样按钮（手机用，hold 键按下时也亮起）
                _PillChip(
                  icon: Icons.colorize,
                  label: tr('spotRemoveSample'),
                  isActive: isSampling,
                  onTap: notifier.toggleSamplingButton,
                ),
              ],
              const Spacer(),
            ],
          ),
        ),

        // ── 取样提示 + 半径滑块（激活时显示）──
        if (isActive) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              state.cloneSource != null
                  ? tr('spotRemoveSourceSet')
                  : tr('spotRemoveAltHint'),
              style: AppTypography.labelSmall.copyWith(
                color: state.cloneSource != null
                    ? AppColors.semanticSuccess
                    : AppColors.disabledText,
              ),
            ),
          ),
          const SizedBox(height: 4),
          DevelopSliderTile(
            label: tr('spotRemoveRadius'),
            value: state.brushRadius * 1000,
            min: 2,
            max: 100,
            fractionDigits: 0,
            suffix: '‰',
            onChanged: (v) => notifier.setBrushRadius(v / 1000),
          ),
          DevelopSliderTile(
            label: tr('spotRemoveHardness'),
            value: state.brushHardness * 100,
            min: 0,
            max: 100,
            fractionDigits: 0,
            suffix: '%',
            onChanged: (v) => notifier.setBrushHardness(v / 100),
          ),
        ],

        // ── 清除全部 ──
        if (isActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: notifier.clearAll,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(tr('spotRemoveClearAll')),
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

class _PillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PillChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.activeBg : AppColors.dividerLine,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.lightBorder.withValues(alpha: 0.6)
                : AppColors.subtleBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppColors.activeValue : AppColors.mediumText,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isActive ? AppColors.activeValue : AppColors.mediumText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
