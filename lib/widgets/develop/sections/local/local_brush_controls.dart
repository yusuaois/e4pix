import 'package:e4pix/core/theme/app_colors.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/local_adjustment.dart';
import '../../../../core/models/mask_shape.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../services/local/sam_session.dart';
import '../../../../state/providers.dart';
import 'local_section.dart';

class BrushControls extends ConsumerWidget {
  final LocalAdjustment local;
  const BrushControls({super.key, required this.local});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mask = local.mask;
    if (mask is! BrushMask) return const SizedBox.shrink();

    final brush = ref.watch(brushSettingsProvider);
    final mode = brush.mode;
    final busy = brush.wandBusy;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<BrushMode>(
            segments: [
              ButtonSegment(
                value: BrushMode.paint,
                label: Text(tr("brush"), style: AppTypography.labelSmall),
                icon: Icon(Icons.brush, size: 14),
              ),
              ButtonSegment(
                value: BrushMode.wand,
                label: Text(
                  tr("localBrushIntellgentArea"),
                  style: AppTypography.labelSmall,
                ),
                icon: Icon(Icons.auto_fix_high, size: 14),
              ),
              ButtonSegment(
                value: BrushMode.subject,
                label: Text(
                  tr("localBrushSubject"),
                  style: AppTypography.labelSmall,
                ),
                icon: Icon(Icons.center_focus_strong, size: 14),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) {
              ref.read(brushSettingsProvider.notifier).setMode(s.first);
              if (s.first != BrushMode.subject) {
                SamSession.instance.resetPoints();
              }
            },
          ),
        ),
        if (mode == BrushMode.wand)
          _wandControls(ref, busy)
        else if (mode == BrushMode.subject)
          _subjectControls(ref, local.id)
        else
          _paintControls(ref),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${tr("localBrushStroke", args: ["${mask.strokes.length}"])}${mask.baseRaster != null ? tr("localBrushIntellgentAreaChosen") : ""}',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.disabledText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (mask.baseRaster != null)
                  TextButton(
                    onPressed: () {
                      LocalAdjustmentActions(ref).clearBaseRaster(local.id);
                      SamSession.instance.resetPoints();
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      tr("localBrushIntellgentAreaClear"),
                      style: AppTypography.labelSmall,
                    ),
                  ),
                if (mask.strokes.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        LocalAdjustmentActions(ref).clearBrushStrokes(local.id),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      tr("localBrushStrokeClear"),
                      style: AppTypography.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _wandControls(WidgetRef ref, bool busy) {
    final tol = ref.watch(brushSettingsProvider.select((s) => s.wandTolerance));
    final invert = ref.watch(brushSettingsProvider.select((s) => s.wandInvert));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Icon(
                busy ? Icons.hourglass_top : Icons.touch_app,
                size: 13,
                color: AppColors.faintText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  busy
                      ? tr("localBrushIntellgentAreaCalculating")
                      : tr("localBrushIntellgentAreaHint"),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.faintText,
                  ),
                ),
              ),
            ],
          ),
        ),
        MiniSlider(
          label: tr("localBrushAutoMaskTolerance"),
          value: tol,
          min: 0.02,
          max: 0.4,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) =>
              ref.read(brushSettingsProvider.notifier).setWandTolerance(v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  tr("localBrushInverse"),
                  style: AppTypography.labelMedium,
                ),
              ),
              Switch(
                value: invert,
                onChanged: (v) =>
                    ref.read(brushSettingsProvider.notifier).setWandInvert(v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _subjectControls(WidgetRef ref, String maskId) {
    final brush = ref.watch(brushSettingsProvider);
    final busy = brush.samBusy;
    final unavailable = brush.samUnavailable;
    final invert = brush.wandInvert;
    final negative = brush.samNegative;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Icon(
                busy ? Icons.hourglass_top : Icons.touch_app,
                size: 13,
                color: AppColors.faintText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  unavailable
                      ? tr("localBrushSubjectUnavailable")
                      : busy
                      ? tr("localBrushSubjectDividing")
                      : negative
                      ? tr("localBrushSubjectExcludeHint")
                      : tr("localBrushSubjectHint"),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.faintText,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  tr("localBrushSubjectExcludeAdd"),
                  style: AppTypography.labelSmall,
                ),
                icon: Icon(Icons.add, size: 14),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  tr("localBrushSubjectExcludeSubtract"),
                  style: AppTypography.labelSmall,
                ),
                icon: Icon(Icons.remove, size: 14),
              ),
            ],
            selected: {negative},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => ref
                .read(brushSettingsProvider.notifier)
                .setSamNegative(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  tr("localBrushInverse"),
                  style: AppTypography.labelMedium,
                ),
              ),
              Switch(
                value: invert,
                onChanged: (v) =>
                    ref.read(brushSettingsProvider.notifier).setWandInvert(v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paintControls(WidgetRef ref) {
    final brush = ref.watch(brushSettingsProvider);
    final radius = brush.radius;
    final hardness = brush.hardness;
    final erase = brush.erase;
    final flow = brush.flow;
    final auto = brush.autoMask;
    final tol = brush.tolerance;
    final edge = brush.edgeStrength;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  tr("localBrushMode"),
                  style: AppTypography.labelMedium,
                ),
              ),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(
                        tr("localBrushModePaint"),
                        style: AppTypography.labelSmall,
                      ),
                      icon: Icon(Icons.add, size: 14),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(
                        tr("localBrushModeErase"),
                        style: AppTypography.labelSmall,
                      ),
                      icon: Icon(Icons.remove, size: 14),
                    ),
                  ],
                  selected: {erase},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (s) => ref
                      .read(brushSettingsProvider.notifier)
                      .setErase(s.first),
                ),
              ),
            ],
          ),
        ),
        MiniSlider(
          label: tr("localBrushSize"),
          value: radius,
          min: 0.01,
          max: 0.30,
          formatter: (v) => (v * 100).toStringAsFixed(0),
          onChanged: (v) =>
              ref.read(brushSettingsProvider.notifier).setRadius(v),
        ),
        MiniSlider(
          label: tr("localBrushHardness"),
          value: hardness,
          min: 0,
          max: 1,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) =>
              ref.read(brushSettingsProvider.notifier).setHardness(v),
        ),
        MiniSlider(
          label: tr("localBrushFlow"),
          value: flow,
          min: 0.05,
          max: 1.0,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) => ref.read(brushSettingsProvider.notifier).setFlow(v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  tr("localBrushAutoMask"),
                  style: AppTypography.labelMedium,
                ),
              ),
              Switch(
                value: auto,
                onChanged: (v) =>
                    ref.read(brushSettingsProvider.notifier).setAutoMask(v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Spacer(),
              Text(
                tr("localBrushEdgeSnap"),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.disabledText,
                ),
              ),
            ],
          ),
        ),
        if (auto) ...[
          MiniSlider(
            label: tr("localBrushAutoMaskTolerance"),
            value: tol,
            min: 0.02,
            max: 0.6,
            formatter: (v) => (v * 100).round().toString(),
            onChanged: (v) =>
                ref.read(brushSettingsProvider.notifier).setTolerance(v),
          ),
          MiniSlider(
            label: tr("localBrushAutoMaskEdgeStrength"),
            value: edge,
            min: 0.0,
            max: 1.0,
            formatter: (v) => (v * 100).round().toString(),
            onChanged: (v) =>
                ref.read(brushSettingsProvider.notifier).setEdgeStrength(v),
          ),
        ],
      ],
    );
  }
}
