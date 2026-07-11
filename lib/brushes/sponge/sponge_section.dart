import 'sponge_state.dart';
import 'sponge_model.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/develop/sections/shared.dart';

/// 海绵工具设置面板
///
/// - 激活切换 PillChip
/// - 饱和/去饱和模式切换
/// - 流量/半径/硬度滑块
/// - 清除全部按钮
class SpongeSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const SpongeSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spongeStateProvider);
    final notifier = ref.read(spongeStateProvider.notifier);
    final isActive = state.brushMode == SpongeBrushMode.active;
    final marks = (params.brushMarks['sponge']?.cast<SpongeMark>()) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'sponge'),

        // 激活切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              PillChip(
                icon: Icons.water_drop,
                label: tr('spongeTitle'),
                isActive: isActive,
                onTap: () => notifier.setBrushMode(
                  isActive ? SpongeBrushMode.inactive : SpongeBrushMode.active,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),

        // 控件（激活时显示）
        if (isActive) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              tr('spongeHint'),
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.disabledText,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 饱和/去饱和 模式切换
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                PillChip(
                  icon: Icons.add_circle_outline,
                  label: tr('spongeSaturate'),
                  isActive: state.mode == SpongeMode.saturate,
                  onTap: () => notifier.setMode(SpongeMode.saturate),
                ),
                const SizedBox(width: 8),
                PillChip(
                  icon: Icons.remove_circle_outline,
                  label: tr('spongeDesaturate'),
                  isActive: state.mode == SpongeMode.desaturate,
                  onTap: () => notifier.setMode(SpongeMode.desaturate),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          DevelopSliderTile(
            label: tr('spongeFlow'),
            value: state.flow * 100,
            min: 1,
            max: 100,
            fractionDigits: 0,
            suffix: '%',
            onChanged: (v) => notifier.setFlow(v / 100),
          ),
          DevelopSliderTile(
            label: tr('spongeRadius'),
            value: state.brushRadius,
            min: 2,
            max: 100,
            fractionDigits: 0,
            suffix: '‰',
            onChanged: (v) => notifier.setBrushRadius(v),
          ),
          DevelopSliderTile(
            label: tr('spongeHardness'),
            value: state.brushHardness * 100,
            min: 0,
            max: 100,
            fractionDigits: 0,
            suffix: '%',
            onChanged: (v) => notifier.setBrushHardness(v / 100),
          ),
        ],

        // 清除全部
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
