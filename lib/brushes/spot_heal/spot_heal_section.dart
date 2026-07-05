import 'spot_heal_state.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/develop/sections/shared.dart';

/// 污点修复 (Spot Heal) 设置面板
///
/// 与图章/修复画笔一致的布局风格：
/// - 标题
/// - 激活切换 PillChip
/// - 提示文字
/// - 半径/硬度滑块
/// - 清除全部按钮
class SpotHealSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const SpotHealSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spotHealStateProvider);
    final notifier = ref.read(spotHealStateProvider.notifier);
    final isActive = state.mode == SpotHealMode.active;
    final marks = params.spotHealMarks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'spotHeal'),

        // ── 激活切换 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              PillChip(
                icon: Icons.auto_fix_normal,
                label: tr('spotHealTitle'),
                isActive: isActive,
                onTap: () => notifier.setMode(
                  isActive ? SpotHealMode.inactive : SpotHealMode.active,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),

        // ── 提示 + 半径/硬度滑块（激活时显示）──
        if (isActive) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              tr('spotHealHint'),
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.disabledText,
              ),
            ),
          ),
          const SizedBox(height: 4),
          DevelopSliderTile(
            label: tr('spotHealRadius'),
            value: state.brushRadius,
            min: 2,
            max: 100,
            fractionDigits: 0,
            suffix: '‰',
            onChanged: (v) => notifier.setBrushRadius(v),
          ),
          DevelopSliderTile(
            label: tr('spotHealHardness'),
            value: state.brushHardness * 100,
            min: 0,
            max: 100,
            fractionDigits: 0,
            suffix: '%',
            onChanged: (v) => notifier.setBrushHardness(v / 100),
          ),
        ],

        // ── 清除全部 ──
        if (isActive && marks.isNotEmpty)
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
