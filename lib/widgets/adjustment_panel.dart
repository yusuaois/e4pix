import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';

class AdjustmentPanel extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const AdjustmentPanel({super.key, required this.params, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          _Header(onReset: () => onChanged(AdjustmentParams.neutral)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _Section('Light'),
                _slider('Exposure', params.exposure, -5, 5,
                    (v) => onChanged(params.copyWith(exposure: v)),
                    suffix: ' EV', precision: 2),
                _slider('Contrast', params.contrast, -100, 100,
                    (v) => onChanged(params.copyWith(contrast: v))),
                _slider('Highlights', params.highlights, -100, 100,
                    (v) => onChanged(params.copyWith(highlights: v))),
                _slider('Shadows', params.shadows, -100, 100,
                    (v) => onChanged(params.copyWith(shadows: v))),
                _slider('Whites', params.whites, -100, 100,
                    (v) => onChanged(params.copyWith(whites: v))),
                _slider('Blacks', params.blacks, -100, 100,
                    (v) => onChanged(params.copyWith(blacks: v))),

                _Section('White Balance'),
                _slider('Temp', params.temperature.toDouble(), 2000, 12000,
                    (v) => onChanged(params.copyWith(temperature: v.round())),
                    suffix: ' K', precision: 0),
                _slider('Tint', params.tint, -100, 100,
                    (v) => onChanged(params.copyWith(tint: v))),

                _Section('Color'),
                _slider('Saturation', params.saturation, -100, 100,
                    (v) => onChanged(params.copyWith(saturation: v))),
                _slider('Vibrance', params.vibrance, -100, 100,
                    (v) => onChanged(params.copyWith(vibrance: v))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label, double value, double min, double max,
    ValueChanged<double> onChange, {
    String suffix = '',
    int precision = 0,
  }) {
    return _SliderTile(
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: onChange,
      suffix: suffix,
      precision: precision,
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onReset;
  const _Header({required this.onReset});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          const Text('Develop',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Reset all',
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.4,
          color: Colors.white.withOpacity(0.4),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String suffix;
  final int precision;
  const _SliderTile({
    required this.label, required this.value,
    required this.min, required this.max,
    required this.onChanged,
    this.suffix = '', this.precision = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasZeroDetent = min < 0 && max > 0;
    final zeroValue = hasZeroDetent ? 0.0 : (min + max) / 2;
    final isNeutral = (value - zeroValue).abs() < 0.001;
    final display = value.toStringAsFixed(precision);
    final sign = !hasZeroDetent || value <= 0 ? '' : '+';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label,
                  style: const TextStyle(fontSize: 12.5))),
              GestureDetector(
                onDoubleTap: () => onChanged(zeroValue),
                child: Text(
                  '$sign$display$suffix',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: isNeutral
                        ? Colors.white.withOpacity(0.4)
                        : Colors.greenAccent.withOpacity(0.85),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
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