import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/local_adjustment.dart';
import '../../../core/models/mask_shape.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/local/sam_session.dart';
import '../../../state/providers.dart';
import '../develop_sections.dart';
import '../tracked_slider.dart';
import 'local/local_shape_controls.dart';
import 'local/local_brush_controls.dart';
import 'local/local_params_controls.dart';

class LocalPanel extends ConsumerWidget {
  const LocalPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locals = ref.watch(
      currentParamsNotifierProvider.select((p) => p.locals),
    );
    final selectedId = ref.watch(selectedLocalIdProvider);
    final selected = ref.watch(selectedLocalProvider);
    final atLimit = locals.length >= LocalAdjustmentActions.maxLocals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Local'),
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addLinear(),
                  child: Text(
                    tr("linear"),
                    style: AppTypography.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addRadial(),
                  child: Text(
                    tr("radial"),
                    style: AppTypography.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addBrush(),
                  child: Text(
                    tr("brush"),
                    style: AppTypography.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (locals.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 16, 8),
            child: Text(
              tr("notAddedLocalAdjustment"),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.disabledText,
              ),
            ),
          )
        else
          for (final local in locals)
            _MaskListItem(local: local, isSelected: local.id == selectedId),
        if (selected != null) ...[
          const SizedBox(height: 6),
          Divider(height: 1, color: AppColors.faintBorder),
          LocalShapeControls(local: selected),
          BrushControls(local: selected),
          Divider(height: 1, color: AppColors.faintBorder),
          LocalParamsControls(local: selected),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextButton(
              onPressed: () =>
                  ref.read(selectedLocalIdProvider.notifier).state = null,
              child: Text(tr("completed"), style: AppTypography.labelSmall),
            ),
          ),
        ],
      ],
    );
  }
}

class _MaskListItem extends ConsumerWidget {
  final LocalAdjustment local;
  final bool isSelected;
  const _MaskListItem({required this.local, required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mask = local.mask;
    final icon = mask is LinearGradientMask
        ? Icons.gradient
        : mask is RadialGradientMask
        ? Icons.brightness_5
        : Icons.brush;
    final color = isSelected ? AppColors.textPrimary : AppColors.mediumText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => {
          ref.read(selectedLocalIdProvider.notifier).state = local.id,
          SamSession.instance.resetPoints(),
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: isSelected ? AppColors.subtleBorder : Colors.transparent,
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  local.name,
                  style: AppTypography.bodyLarge.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  local.enabled ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: AppColors.faintText,
                ),
                onPressed: () => LocalAdjustmentActions(
                  ref,
                ).updateLocal(local.id, (l) => l.copyWith(enabled: !l.enabled)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 14, color: AppColors.faintText),
                onPressed: () => {
                  LocalAdjustmentActions(ref).deleteLocal(local.id),
                  SamSession.instance.resetPoints(),
                },
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double)? formatter;
  const MiniSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: AppTypography.labelMedium),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 2),
              child: TrackedSlider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              formatter != null ? formatter!(value) : value.round().toString(),
              textAlign: TextAlign.right,
              style: AppTypography.labelMedium.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
