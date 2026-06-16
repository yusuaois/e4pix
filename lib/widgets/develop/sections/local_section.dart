import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/local_adjustment.dart';
import '../../../core/models/mask_shape.dart';
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
    final params = ref.watch(currentParamsNotifierProvider);
    final selectedId = ref.watch(selectedLocalIdProvider);
    final selected = ref.watch(selectedLocalProvider);
    final atLimit = params.locals.length >= LocalAdjustmentActions.maxLocals;

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
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.gradient, size: 14),
                  label: Text(tr("linear"), style: TextStyle(fontSize: 10)),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addLinear(),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.brightness_5, size: 14),
                  label: Text(tr("radial"), style: TextStyle(fontSize: 10)),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addRadial(),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.brush, size: 14),
                  label: Text(tr("brush"), style: TextStyle(fontSize: 10)),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addBrush(),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (params.locals.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 16, 8),
            child: Text(
              tr("notAddedLocalAdjustment"),
              style: TextStyle(fontSize: 10.5, color: AppColors.disabledText),
            ),
          )
        else
          for (final local in params.locals)
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
              child: Text(tr("completed"), style: TextStyle(fontSize: 10)),
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
                  style: TextStyle(fontSize: 12, color: color),
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
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 14, color: AppColors.faintText),
                onPressed: () => {
                  LocalAdjustmentActions(ref).deleteLocal(local.id),
                  SamSession.instance.resetPoints(),
                },
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
            child: Text(label, style: const TextStyle(fontSize: 10.5)),
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
              style: const TextStyle(
                fontSize: 10.5,
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
