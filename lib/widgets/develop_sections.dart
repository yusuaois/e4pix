import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/hsl_bands.dart';

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
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
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
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min, max: max,
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
              color: Colors.white.withOpacity(0.4),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

// Light Section
class LightSection extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const LightSection({super.key, required this.params, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Light'),
        DevelopSliderTile(
          label: '曝光', value: p.exposure, min: -5, max: 5,
          onChanged: (v) => onChanged(p.copyWith(exposure: v)),
          suffix: ' EV', precision: 2,
        ),
        DevelopSliderTile(
          label: '对比度', value: p.contrast, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(contrast: v)),
        ),
        DevelopSliderTile(
          label: '高光', value: p.highlights, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(highlights: v)),
        ),
        DevelopSliderTile(
          label: '阴影', value: p.shadows, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(shadows: v)),
        ),
        DevelopSliderTile(
          label: '白场', value: p.whites, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(whites: v)),
        ),
        DevelopSliderTile(
          label: '黑场', value: p.blacks, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(blacks: v)),
        ),
      ],
    );
  }
}

// White Balance + Color Section
class WhiteBalanceColorSection extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const WhiteBalanceColorSection({super.key, required this.params, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'White Balance'),
        DevelopSliderTile(
          label: '白平衡',
          value: p.temperature.toDouble(),
          min: 2000, max: 12000,
          onChanged: (v) => onChanged(p.copyWith(temperature: v.round())),
          suffix: ' K',
        ),
        DevelopSliderTile(
          label: '色调', value: p.tint, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(tint: v)),
        ),
        const SectionLabel(title: 'Color'),
        DevelopSliderTile(
          label: '饱和度', value: p.saturation, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(saturation: v)),
        ),
        DevelopSliderTile(
          label: '自然饱和度', value: p.vibrance, min: -100, max: 100,
          onChanged: (v) => onChanged(p.copyWith(vibrance: v)),
        ),
      ],
    );
  }
}

// HSL Section
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
    Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFDD835), Color(0xFF43A047),
    Color(0xFF00ACC1), Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFFD81B60),
  ];
  static const _bandLabels = [
    '红色', '橙色', '黄色', '绿色', '青色', '蓝色', '紫色', '品红色',
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
                      color: Colors.white.withOpacity(0.5),
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
            segments: const [
              ButtonSegment(value: 0, label: Text('色相')),
              ButtonSegment(value: 1, label: Text('饱和度')),
              ButtonSegment(value: 2, label: Text('明度')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(8, (i) => _BandRow(
              color: _bandColors[i],
              label: _bandLabels[i],
              value: values[i],
              onChanged: (v) => _setValue(i, v),
            )),
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
    required this.color, required this.label,
    required this.value, required this.onChanged,
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
            width: 14, height: 14,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 11.5))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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

// LUT Section
class LutSection extends StatelessWidget {
  final String? lutName;
  final double intensity;
  final ValueChanged<double> onIntensityChanged;
  final VoidCallback? onPick, onLoadTest, onLoadIdentity, onClear;

  const LutSection({
    super.key,
    required this.lutName,
    required this.intensity,
    required this.onIntensityChanged,
    this.onPick, this.onLoadTest, this.onLoadIdentity, this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final loaded = lutName != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'LUT'),
        if (loaded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
            child: Row(
              children: [
                Icon(Icons.gradient,
                    size: 14, color: Colors.greenAccent.withOpacity(0.7)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(lutName!,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove',
                  onPressed: onClear,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(
                    width: 64,
                    child: Text('Intensity', style: TextStyle(fontSize: 11.5))),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: intensity.clamp(0.0, 1.0),
                      onChanged: onIntensityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(intensity * 100).round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Colors.greenAccent.withOpacity(0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
            child: Text('未加载',
                style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.4))),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.folder_open, size: 14),
                  label: const Text('.cube', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: onLoadTest,
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Test', style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: onLoadIdentity,
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Ident', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}