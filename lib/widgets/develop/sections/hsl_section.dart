import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/models/hsl_bands.dart';
import '../tracked_slider.dart';
import 'shared.dart';

class HslSection extends StatefulWidget {
  final HslBands bands;
  final ValueChanged<HslBands> onChanged;
  const HslSection({super.key, required this.bands, required this.onChanged});

  @override
  State<HslSection> createState() => _HslSectionState();
}

class _HslSectionState extends State<HslSection> {
  int _mode = 0; // 0=Hue, 1=Sat, 2=Lum

  static const _bandColors = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
  ];
  final _bandLabels = [
    tr("red"),
    tr("orange"),
    tr("yellow"),
    tr("green"),
    tr("cyan"),
    tr("blue"),
    tr("purple"),
    tr("magenta"),
  ];

  List<double> _values() => switch (_mode) {
    0 => widget.bands.hues,
    1 => widget.bands.sats,
    _ => widget.bands.lums,
  };

  void _setValue(int index, double v) {
    final updated = switch (_mode) {
      0 => widget.bands.setHue(index, v),
      1 => widget.bands.setSat(index, v),
      _ => widget.bands.setLum(index, v),
    };
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final values = _values();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          title: 'HSL / Color',
          trailing: !widget.bands.isNeutral
              ? GestureDetector(
                  onTap: () => widget.onChanged(HslBands.neutral),
                  child: Text(
                    'reset',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
            segments: [
              ButtonSegment(value: 0, label: Text(tr("hue"))),
              ButtonSegment(value: 1, label: Text(tr("sat"))),
              ButtonSegment(value: 2, label: Text(tr("lum"))),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          8,
          (i) => _BandRow(
            color: _bandColors[i],
            label: _bandLabels[i],
            value: values[i],
            onChanged: (v) => _setValue(i, v),
          ),
        ),
      ],
    );
  }
}

class _BandRow extends StatelessWidget {
  final Color color;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _BandRow({
    required this.color,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isNeutral = value.abs() < 0.01;
    final sign = value > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 11.5)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: TrackedSlider(
                value: value.clamp(-100.0, 100.0),
                min: -100,
                max: 100,
                onChanged: onChanged,
              ),
            ),
          ),
          GestureDetector(
            onDoubleTap: () => onChanged(0),
            child: SizedBox(
              width: 36,
              child: Text(
                '$sign${value.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: isNeutral
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.greenAccent.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
