import 'package:flutter/material.dart';

import '../tracked_slider.dart';

// 通用滑块 tile
class DevelopSliderTile extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String suffix;
  final int precision;

  const DevelopSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
    this.precision = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasZeroDetent = min < 0 && max > 0;
    final zeroValue = hasZeroDetent ? 0.0 : (min + max) / 2;
    final isNeutral = (value - zeroValue).abs() < 0.001;
    final display = value.toStringAsFixed(precision);
    final sign = !hasZeroDetent || value <= 0 ? '' : '+';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12.5)),
              ),
              GestureDetector(
                onDoubleTap: () => onChanged(zeroValue),
                child: Text(
                  '$sign$display$suffix',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: isNeutral
                        ? Colors.white.withValues(alpha: 0.4)
                        : Colors.greenAccent.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: TrackedSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// Section 标签
class SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionLabel({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.4),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}
