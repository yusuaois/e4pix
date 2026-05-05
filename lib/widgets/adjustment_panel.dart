import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/hsl_bands.dart';

class AdjustmentPanel extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const AdjustmentPanel({
    super.key,
    required this.params,
    required this.onChanged,
  });

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
                _slider(
                  'Exposure',
                  params.exposure,
                  -5,
                  5,
                  (v) => onChanged(params.copyWith(exposure: v)),
                  suffix: ' EV',
                  precision: 2,
                ),
                _slider(
                  'Contrast',
                  params.contrast,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(contrast: v)),
                ),
                _slider(
                  'Highlights',
                  params.highlights,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(highlights: v)),
                ),
                _slider(
                  'Shadows',
                  params.shadows,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(shadows: v)),
                ),
                _slider(
                  'Whites',
                  params.whites,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(whites: v)),
                ),
                _slider(
                  'Blacks',
                  params.blacks,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(blacks: v)),
                ),

                _Section('White Balance'),
                _slider(
                  'Temp',
                  params.temperature.toDouble(),
                  2000,
                  12000,
                  (v) => onChanged(params.copyWith(temperature: v.round())),
                  suffix: ' K',
                  precision: 0,
                ),
                _slider(
                  'Tint',
                  params.tint,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(tint: v)),
                ),

                _Section('Color'),
                _slider(
                  'Saturation',
                  params.saturation,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(saturation: v)),
                ),
                _slider(
                  'Vibrance',
                  params.vibrance,
                  -100,
                  100,
                  (v) => onChanged(params.copyWith(vibrance: v)),
                ),
                const SizedBox(height: 8),
                _HslSection(
                  bands: params.hsl,
                  onChanged: (b) => onChanged(params.copyWith(hsl: b)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
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
          const Text(
            'Develop',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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

// ============================================================================
// HSL 8 段子面板
// ============================================================================
class _HslSection extends StatefulWidget {
  final HslBands bands;
  final ValueChanged<HslBands> onChanged;
  const _HslSection({required this.bands, required this.onChanged});

  @override
  State<_HslSection> createState() => _HslSectionState();
}

class _HslSectionState extends State<_HslSection> {
  int _mode = 0; // 0=Hue, 1=Sat, 2=Lum

  static const _bandColors = [
    Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835), Color(0xFF43A047),
    Color(0xFF00ACC1), Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFFD81B60),
  ];
  static const _bandLabels = [
    'Red', 'Orange', 'Yellow', 'Green', 'Aqua', 'Blue', 'Purple', 'Magenta',
  ];

  List<double> _values() {
    switch (_mode) {
      case 0: return widget.bands.hues;
      case 1: return widget.bands.sats;
      default: return widget.bands.lums;
    }
  }

  void _setValue(int index, double v) {
    final b = widget.bands;
    final updated = switch (_mode) {
      0 => b.setHue(index, v),
      1 => b.setSat(index, v),
      _ => b.setLum(index, v),
    };
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final values = _values();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Text(
                'HSL / COLOR',
                style: TextStyle(
                  fontSize: 10, letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
              const Spacer(),
              if (!widget.bands.isNeutral)
                GestureDetector(
                  onTap: () => widget.onChanged(HslBands.neutral),
                  child: Text(
                    'reset',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('Hue')),
              ButtonSegment(value: 1, label: Text('Sat')),
              ButtonSegment(value: 2, label: Text('Lum')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(8, (index) => _BandSlider(
          color: _bandColors[index],
          label: _bandLabels[index],
          value: values[index],
          onChanged: (v) => _setValue(index, v),
        )),
      ],
    );
  }
}

class _BandSlider extends StatelessWidget {
  final Color color;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _BandSlider({
    required this.color, required this.label,
    required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isNeutral = value.abs() < 0.01;
    final sign = value > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      child: Row(
        children: [
          Container(
            width: 14, height: 14,
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
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.clamp(-100.0, 100.0),
                min: -100, max: 100,
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
                      ? Colors.white.withOpacity(0.4)
                      : Colors.greenAccent.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
