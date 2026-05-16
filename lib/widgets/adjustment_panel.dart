import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';
import 'develop_sections.dart';

class AdjustmentPanel extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  final Widget? histogram;
  final String? lutName;
  final VoidCallback? onPickLut;
  final VoidCallback? onLoadTestLut;
  final VoidCallback? onLoadIdentity;
  final VoidCallback? onClearLut;

  const AdjustmentPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.histogram,
    this.lutName,
    this.onPickLut,
    this.onLoadTestLut,
    this.onLoadIdentity,
    this.onClearLut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Column(
        children: [
          _Header(onReset: () => onChanged(AdjustmentParams.neutral)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ?histogram,
                LightSection(params: params, onChanged: onChanged),
                WhiteBalanceColorSection(params: params, onChanged: onChanged),
                HslSection(
                  bands: params.hsl,
                  onChanged: (b) => onChanged(params.copyWith(hsl: b)),
                ),
                const SizedBox(height: 8),
                LutSection(
                  lutName: lutName,
                  intensity: params.lutIntensity,
                  onIntensityChanged: (v) =>
                      onChanged(params.copyWith(lutIntensity: v)),
                  onPick: onPickLut,
                  onLoadTest: onLoadTestLut,
                  onLoadIdentity: onLoadIdentity,
                  onClear: onClearLut,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
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
            tooltip: tr("reset"),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}
