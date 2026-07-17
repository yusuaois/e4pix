import 'dodge_burn_state.dart';
import 'dodge_burn_model.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/develop/sections/shared.dart';

/// 加深减淡设置面板（对齐 Photoshop）
///
/// - 激活切换
/// - 减淡/加深模式切换
/// - 阴影/中间调/高光范围选择
/// - 曝光/半径/硬度滑块
/// - 清除全部按钮
class DodgeBurnSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const DodgeBurnSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dodgeBurnStateProvider);
    final notifier = ref.read(dodgeBurnStateProvider.notifier);
    final isActive = state.brushMode == DodgeBurnBrushMode.active;
    final marks =
        (params.brushMarks['dodge_burn']?.cast<DodgeBurnMark>()) ?? const [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(title: 'dodgeBurn'),

          // ── 激活切换 ──
          SwitchTile.tile(
            label: tr('dodgeBurnTitle'),
            value: isActive,
            onChanged: (_) => notifier.setBrushMode(
              isActive
                  ? DodgeBurnBrushMode.inactive
                  : DodgeBurnBrushMode.active,
            ),
          ),

          // ── 控件（激活时显示）──
          if (isActive) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                tr('dodgeBurnHint'),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.disabledText,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Dodge / Burn mode switch
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  PillChip(
                    icon: Icons.light_mode,
                    label: tr('dodgeBurnDodge'),
                    isActive: state.mode == DodgeBurnMode.dodge,
                    onTap: () => notifier.setMode(DodgeBurnMode.dodge),
                  ),
                  const SizedBox(width: 8),
                  PillChip(
                    icon: Icons.dark_mode,
                    label: tr('dodgeBurnBurn'),
                    isActive: state.mode == DodgeBurnMode.burn,
                    onTap: () => notifier.setMode(DodgeBurnMode.burn),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Shadows / Midtones / Highlights range selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  PillChip(
                    icon: Icons.contrast,
                    label: tr('dodgeBurnShadows'),
                    isActive: state.range == DodgeBurnRange.shadows,
                    onTap: () => notifier.setRange(DodgeBurnRange.shadows),
                  ),
                  const SizedBox(width: 4),
                  PillChip(
                    icon: Icons.contrast,
                    label: tr('dodgeBurnMidtones'),
                    isActive: state.range == DodgeBurnRange.midtones,
                    onTap: () => notifier.setRange(DodgeBurnRange.midtones),
                  ),
                  const SizedBox(width: 4),
                  PillChip(
                    icon: Icons.contrast,
                    label: tr('dodgeBurnHighlights'),
                    isActive: state.range == DodgeBurnRange.highlights,
                    onTap: () => notifier.setRange(DodgeBurnRange.highlights),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            DevelopSliderTile(
              label: tr('dodgeBurnExposure'),
              value: state.exposure * 100,
              min: 1,
              max: 100,
              fractionDigits: 0,
              suffix: '%',
              onChanged: (v) => notifier.setExposure(v / 100),
            ),
            DevelopSliderTile(
              label: tr('dodgeBurnRadius'),
              value: state.brushRadius,
              min: 2,
              max: 100,
              fractionDigits: 0,
              suffix: '‰',
              onChanged: (v) => notifier.setBrushRadius(v),
            ),
            DevelopSliderTile(
              label: tr('dodgeBurnHardness'),
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
      ),
    );
  }
}
