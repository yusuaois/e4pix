import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';
import '../../widgets/develop/sections/history_panel_sheet.dart';
import '../../widgets/develop/sections/shared.dart';
import 'history_brush_model.dart';
import 'history_brush_state.dart';

class HistoryBrushSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  const HistoryBrushSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyBrushStateProvider);
    final notifier = ref.read(historyBrushStateProvider.notifier);
    final brushSourceIndex = ref.watch(historyPanelProvider).brushSourceIndex;
    final isActive = state.mode == HistoryBrushMode.active;
    final marks =
        (params.brushMarks['history_brush']?.cast<HistoryMark>()) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'historyBrush'),

        // 激活按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              PillChip(
                icon: Icons.history,
                label: tr('historyBrushTitle'),
                isActive: isActive,
                onTap: () {
                  if (isActive) {
                    notifier.setMode(HistoryBrushMode.inactive);
                  } else {
                    notifier.setMode(HistoryBrushMode.active);
                    if (brushSourceIndex == null) {
                      showHistoryPanelSheet(context, ref);
                    }
                  }
                },
              ),
              const Spacer(),
            ],
          ),
        ),

        // 画笔源状态
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: GestureDetector(
            onTap: brushSourceIndex != null
                ? () =>
                      ref.read(historyPanelProvider.notifier).clearBrushSource()
                : () => showHistoryPanelSheet(context, ref),
            child: Text(
              brushSourceIndex != null
                  ? tr('historyBrushSourceActive')
                  : tr('historyBrushNoSource'),
              style: AppTypography.labelSmall.copyWith(
                color: brushSourceIndex != null
                    ? AppColors.semanticSuccess
                    : AppColors.disabledText,
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),

        if (isActive) ...[
          // 半径滑块
          DevelopSliderTile(
            label: tr('historyBrushRadius'),
            value: state.brushRadius * 1000,
            min: 2,
            max: 100,
            fractionDigits: 0,
            suffix: '‰',
            onChanged: (v) => notifier.setBrushRadius(v / 1000),
          ),

          // 硬度滑块
          DevelopSliderTile(
            label: tr('historyBrushHardness'),
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
