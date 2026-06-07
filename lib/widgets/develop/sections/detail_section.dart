import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/models/adjustment_params.dart';
import '../../../core/models/grain_params.dart';
import '../tracked_slider.dart';
import 'shared.dart';

class DetailSection extends StatefulWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const DetailSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  State<DetailSection> createState() => _DetailSectionState();
}

class _DetailSectionState extends State<DetailSection> {
  bool _grainAdvanced = false;

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required double resetValue,
    int fractionDigits = 0,
  }) {
    return Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                GestureDetector(
                  onDoubleTap: () => onChanged(resetValue),
                  child: Text(
                    value.toStringAsFixed(fractionDigits),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: (value - resetValue).abs() < 0.001
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.params;
    final g = p.grain;
    void setGrain(GrainParams ng) => widget.onChanged(p.copyWith(grain: ng));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Sharpen'),
        _slider(
          label: tr('sharpenAmount'),
          value: p.sharpenAmount,
          min: 0,
          max: 100,
          resetValue: 0,
          onChanged: (v) => widget.onChanged(p.copyWith(sharpenAmount: v)),
        ),
        _slider(
          label: tr('sharpenRadius'),
          value: p.sharpenRadius,
          min: 0.5,
          max: 3.0,
          fractionDigits: 1,
          resetValue: 1.0,
          onChanged: (v) => widget.onChanged(p.copyWith(sharpenRadius: v)),
        ),
        _slider(
          label: tr('sharpenMasking'),
          value: p.sharpenMasking,
          min: 0,
          max: 100,
          resetValue: 0,
          onChanged: (v) => widget.onChanged(p.copyWith(sharpenMasking: v)),
        ),
        const SectionLabel(title: 'Denoise'),
        _slider(
          label: tr('denoiseLuma'),
          value: p.denoiseLuma,
          min: 0,
          max: 100,
          resetValue: 0,
          onChanged: (v) => widget.onChanged(p.copyWith(denoiseLuma: v)),
        ),
        _slider(
          label: tr('denoiseColor'),
          value: p.denoiseColor,
          min: 0,
          max: 100,
          resetValue: 0,
          onChanged: (v) => widget.onChanged(p.copyWith(denoiseColor: v)),
        ),
        const SectionLabel(title: 'Grain'),
        _slider(
          label: tr('grainAmount'),
          value: g.amount,
          min: 0,
          max: 100,
          resetValue: 0,
          onChanged: (v) => setGrain(g.copyWith(amount: v)),
        ),
        _slider(
          label: tr('grainSize'),
          value: g.size,
          min: 0.1,
          max: 10.0,
          fractionDigits: 1,
          resetValue: 1.0,
          onChanged: (v) => setGrain(g.copyWith(size: v)),
        ),
        InkWell(
          onTap: () => setState(() => _grainAdvanced = !_grainAdvanced),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              children: [
                Text(
                  tr('grainAdvanced').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: Colors.white.withValues(
                      alpha: _grainAdvanced ? 0.6 : 0.4,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _grainAdvanced ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: Colors.white.withValues(
                      alpha: _grainAdvanced ? 0.6 : 0.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _grainAdvanced ? 1.0 : 0.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  _slider(
                    label: tr('grainShadowThreshold'),
                    value: g.shadowThreshold,
                    min: 0,
                    max: 255,
                    resetValue: 85,
                    onChanged: (v) => setGrain(g.copyWith(shadowThreshold: v)),
                  ),
                  _slider(
                    label: tr('grainHighlightThreshold'),
                    value: g.highlightThreshold,
                    min: 0,
                    max: 255,
                    resetValue: 170,
                    onChanged: (v) =>
                        setGrain(g.copyWith(highlightThreshold: v)),
                  ),
                  _slider(
                    label: tr('grainShadowStrength'),
                    value: g.shadowStrength,
                    min: 0.2,
                    max: 1.0,
                    fractionDigits: 2,
                    resetValue: 0.6,
                    onChanged: (v) => setGrain(g.copyWith(shadowStrength: v)),
                  ),
                  _slider(
                    label: tr('grainHighlightStrength'),
                    value: g.highlightStrength,
                    min: 0.1,
                    max: 0.8,
                    fractionDigits: 2,
                    resetValue: 0.3,
                    onChanged: (v) =>
                        setGrain(g.copyWith(highlightStrength: v)),
                  ),
                  _slider(
                    label: tr('grainShadowSize'),
                    value: g.shadowSize,
                    min: 1.0,
                    max: 2.0,
                    fractionDigits: 2,
                    resetValue: 1.5,
                    onChanged: (v) => setGrain(g.copyWith(shadowSize: v)),
                  ),
                  _slider(
                    label: tr('grainHighlightSize'),
                    value: g.highlightSize,
                    min: 0.3,
                    max: 1.0,
                    fractionDigits: 2,
                    resetValue: 0.6,
                    onChanged: (v) => setGrain(g.copyWith(highlightSize: v)),
                  ),
                  _slider(
                    label: tr('grainRedChannel'),
                    value: g.redRatio,
                    min: 0.5,
                    max: 1.5,
                    fractionDigits: 2,
                    resetValue: 0.9,
                    onChanged: (v) => setGrain(g.copyWith(redRatio: v)),
                  ),
                  _slider(
                    label: tr('grainBlueChannel'),
                    value: g.blueRatio,
                    min: 0.8,
                    max: 1.5,
                    fractionDigits: 2,
                    resetValue: 1.2,
                    onChanged: (v) => setGrain(g.copyWith(blueRatio: v)),
                  ),
                  _slider(
                    label: tr('grainCorrelation'),
                    value: g.correlation,
                    min: 0.8,
                    max: 0.95,
                    fractionDigits: 2,
                    resetValue: 0.9,
                    onChanged: (v) => setGrain(g.copyWith(correlation: v)),
                  ),
                  _slider(
                    label: tr('grainColorPreservation'),
                    value: g.colorPreservation,
                    min: 0.9,
                    max: 1.0,
                    fractionDigits: 2,
                    resetValue: 0.95,
                    onChanged: (v) =>
                        setGrain(g.copyWith(colorPreservation: v)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
