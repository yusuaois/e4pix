import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/local_adjustment.dart';
import '../core/models/local_params.dart';
import '../core/models/mask_shape.dart';
import '../state/local_state.dart';
import '../state/params_state.dart';
import 'develop_sections.dart';

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
        const SectionLabel(title: 'LOCAL'),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.gradient, size: 14),
                  label: Text(tr("linear"), style: TextStyle(fontSize: 11)),
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
                  label: Text(tr("radial"), style: TextStyle(fontSize: 11)),
                  onPressed: atLimit
                      ? null
                      : () => LocalAdjustmentActions(ref).addRadial(),
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
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
          )
        else
          for (final local in params.locals)
            _MaskListItem(
              local: local,
              isSelected: local.id == selectedId,
            ),
        if (selected != null) ...[
          const SizedBox(height: 6),
          const Divider(height: 1, color: Colors.white12),
          _LocalShapeControls(local: selected),
          const Divider(height: 1, color: Colors.white12),
          _LocalParamsControls(local: selected),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextButton(
              onPressed: () =>
                  ref.read(selectedLocalIdProvider.notifier).state = null,
              child: Text(tr("completed"), style: TextStyle(fontSize: 11)),
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
    final isLinear = local.mask is LinearGradientMask;
    final color = isSelected
        ? const Color(0xFF6B5BFF)
        : Colors.white.withValues(alpha: 0.7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            ref.read(selectedLocalIdProvider.notifier).state = local.id,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                isLinear ? Icons.gradient : Icons.brightness_5,
                size: 14,
                color: color,
              ),
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
                  color: Colors.white54,
                ),
                onPressed: () => LocalAdjustmentActions(ref).updateLocal(
                  local.id,
                  (l) => l.copyWith(enabled: !l.enabled),
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14, color: Colors.white54),
                onPressed: () =>
                    LocalAdjustmentActions(ref).deleteLocal(local.id),
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

class _LocalShapeControls extends ConsumerWidget {
  final LocalAdjustment local;
  const _LocalShapeControls({required this.local});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = local.mask;
    if (shape is! RadialGradientMask) return const SizedBox.shrink();

    final actions = LocalAdjustmentActions(ref);

    return Column(
      children: [
        _MiniSlider(
          label: tr("rotation"),
          value: shape.rotation,
          min: -3.14159,
          max: 3.14159,
          formatter: (v) => '${(v * 180 / 3.14159).toStringAsFixed(0)}°',
          onChanged: (v) => actions.updateLocal(
            local.id,
            (l) => l.copyWith(mask: shape.copyWith(rotation: v)),
          ),
        ),
        _MiniSlider(
          label: tr("feather"),
          value: shape.feather,
          min: 0,
          max: 1,
          formatter: (v) => (v * 100).round().toString(),
          onChanged: (v) => actions.updateLocal(
            local.id,
            (l) => l.copyWith(mask: shape.copyWith(feather: v)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text(tr("invert"), style: TextStyle(fontSize: 11.5))),
              Switch(
                value: shape.inverted,
                onChanged: (v) => actions.updateLocal(
                  local.id,
                  (l) => l.copyWith(mask: shape.copyWith(inverted: v)),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocalParamsControls extends ConsumerWidget {
  final LocalAdjustment local;
  const _LocalParamsControls({required this.local});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = local.params;
    final actions = LocalAdjustmentActions(ref);

    void update(LocalParams Function(LocalParams) f) {
      actions.updateLocal(local.id, (l) => l.copyWith(params: f(l.params)));
    }

    return Column(
      children: [
        _MiniSlider(
          label: tr("exposure"),
          value: p.exposure,
          min: -3,
          max: 3,
          formatter: (v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(2)}',
          onChanged: (v) => update((q) => q.copyWith(exposure: v)),
        ),
        _MiniSlider(
          label: tr("contrast"),
          value: p.contrast,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(contrast: v)),
        ),
        _MiniSlider(
          label: tr("highlight"),
          value: p.highlights,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(highlights: v)),
        ),
        _MiniSlider(
          label: tr("shadow"),
          value: p.shadows,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(shadows: v)),
        ),
        _MiniSlider(
          label: tr("white"),
          value: p.whites,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(whites: v)),
        ),
        _MiniSlider(
          label: tr("black"),
          value: p.blacks,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(blacks: v)),
        ),
        _MiniSlider(
          label: tr("whiteBalance"),
          value: p.temperatureShift.toDouble(),
          min: -3000,
          max: 3000,
          formatter: (v) =>
              '${v >= 0 ? "+" : ""}${v.round()}',
          onChanged: (v) =>
              update((q) => q.copyWith(temperatureShift: v.round())),
        ),
        _MiniSlider(
          label: tr("tint"),
          value: p.tint,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(tint: v)),
        ),
        _MiniSlider(
          label: tr("saturation"),
          value: p.saturation,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(saturation: v)),
        ),
        _MiniSlider(
          label: tr("vibrance"),
          value: p.vibrance,
          min: -100,
          max: 100,
          onChanged: (v) => update((q) => q.copyWith(vibrance: v)),
        ),
      ],
    );
  }
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double)? formatter;
  const _MiniSlider({
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
            child: Text(label, style: const TextStyle(fontSize: 11.5)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
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
              formatter != null
                  ? formatter!(value)
                  : value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: Colors.greenAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}