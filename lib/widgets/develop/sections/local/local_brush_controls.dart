import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/local_adjustment.dart';
import '../../../../core/models/mask_shape.dart';
import '../../../../services/local/sam_session.dart';
import '../../../../state/providers.dart';
import '../local_section.dart';

class BrushControls extends ConsumerWidget {
  final LocalAdjustment local;
  const BrushControls({super.key, required this.local});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mask = local.mask;
    if (mask is! BrushMask) return const SizedBox.shrink();

    final mode = ref.watch(brushModeProvider);
    final busy = ref.watch(wandBusyProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<BrushMode>(
            segments: [
              ButtonSegment(
                value: BrushMode.paint,
                label: Text(tr("brush"), style: TextStyle(fontSize: 10)),
                icon: Icon(Icons.brush, size: 14),
              ),
              ButtonSegment(
                value: BrushMode.wand,
                label: Text(
                  tr("localBrushIntellgentArea"),
                  style: TextStyle(fontSize: 10),
                ),
                icon: Icon(Icons.auto_fix_high, size: 14),
              ),
              ButtonSegment(
                value: BrushMode.subject,
                label: Text(
                  tr("localBrushSubject"),
                  style: TextStyle(fontSize: 10),
                ),
                icon: Icon(Icons.center_focus_strong, size: 14),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) {
              ref.read(brushModeProvider.notifier).state = s.first;
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
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.white38,
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
                      style: TextStyle(fontSize: 10),
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
                      style: TextStyle(fontSize: 10),
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
    final tol = ref.watch(wandToleranceProvider);
    final invert = ref.watch(wandInvertProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Icon(
                busy ? Icons.hourglass_top : Icons.touch_app,
                size: 13,
                color: Colors.white54,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  busy
                      ? tr("localBrushIntellgentAreaCalculating")
                      : tr("localBrushIntellgentAreaHint"),
                  style: const TextStyle(fontSize: 10.5, color: Colors.white54),
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
          onChanged: (v) => ref.read(wandToleranceProvider.notifier).state = v,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  tr("localBrushInverse"),
                  style: TextStyle(fontSize: 10.5),
                ),
              ),
              Switch(
                value: invert,
                onChanged: (v) =>
                    ref.read(wandInvertProvider.notifier).state = v,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _subjectControls(WidgetRef ref, String maskId) {
    final busy = ref.watch(samBusyProvider);
    final unavailable = ref.watch(samUnavailableProvider);
    final invert = ref.watch(wandInvertProvider);
    final negative = ref.watch(samNegativeProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Row(
            children: [
              Icon(
                busy ? Icons.hourglass_top : Icons.touch_app,
                size: 13,
                color: Colors.white54,
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
                  style: const TextStyle(fontSize: 10.5, color: Colors.white54),
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
                  style: TextStyle(fontSize: 10),
                ),
                icon: Icon(Icons.add, size: 14),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  tr("localBrushSubjectExcludeSubtract"),
                  style: TextStyle(fontSize: 10),
                ),
                icon: Icon(Icons.remove, size: 14),
              ),
            ],
            selected: {negative},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) =>
                ref.read(samNegativeProvider.notifier).state = s.first,
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
                  style: TextStyle(fontSize: 10.5),
                ),
              ),
              Switch(
                value: invert,
                onChanged: (v) =>
                    ref.read(wandInvertProvider.notifier).state = v,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paintControls(WidgetRef ref) {
    final radius = ref.watch(brushRadiusProvider);
    final hardness = ref.watch(brushHardnessProvider);
    final erase = ref.watch(brushEraseProvider);
    final flow = ref.watch(brushFlowProvider);
    final auto = ref.watch(brushAutoMaskProvider);
    final tol = ref.watch(brushToleranceProvider);
    final edge = ref.watch(brushEdgeStrengthProvider);

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
                  style: TextStyle(fontSize: 10.5),
                ),
              ),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(
                        tr("localBrushModePaint"),
                        style: TextStyle(fontSize: 10),
                      ),
                      icon: Icon(Icons.add, size: 14),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(
                        tr("localBrushModeErase"),
                        style: TextStyle(fontSize: 10),
                      ),
                      icon: Icon(Icons.remove, size: 14),
                    ),
                  ],
                  selected: {erase},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (s) =>
                      ref.read(brushEraseProvider.notifier).state = s.first,
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
          onChanged: (v) => ref.read(brushRadiusProvider.notifier).state = v,
        ),
        MiniSlider(
          label: tr("localBrushHardness"),
          value: hardness,
          min: 0,
          max: 1,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) => ref.read(brushHardnessProvider.notifier).state = v,
        ),
        MiniSlider(
          label: tr("localBrushFlow"),
          value: flow,
          min: 0.05,
          max: 1.0,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) => ref.read(brushFlowProvider.notifier).state = v,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  tr("localBrushAutoMask"),
                  style: TextStyle(fontSize: 10.5),
                ),
              ),
              Switch(
                value: auto,
                onChanged: (v) =>
                    ref.read(brushAutoMaskProvider.notifier).state = v,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Spacer(),
              Text(
                tr("localBrushEdgeSnap"),
                style: TextStyle(fontSize: 10, color: Colors.white38),
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
                ref.read(brushToleranceProvider.notifier).state = v,
          ),
          MiniSlider(
            label: tr("localBrushAutoMaskEdgeStrength"),
            value: edge,
            min: 0.0,
            max: 1.0,
            formatter: (v) => (v * 100).round().toString(),
            onChanged: (v) =>
                ref.read(brushEdgeStrengthProvider.notifier).state = v,
          ),
        ],
      ],
    );
  }
}
