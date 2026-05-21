import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../core/models/adjustment_params.dart';
import '../services/lut_library.dart';
import 'develop_sections.dart';
import 'local_panel.dart';

class AdjustmentPanel extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  final Widget? histogram;
  final Widget? presetBar;
  final Widget? info;
  final String? lutName;
  final List<LutEntry> library;
  final ValueChanged<LutEntry?> onSelectLut;
  final Future<void> Function() onImportLut;
  final Future<void> Function(LutEntry) onDeleteLut;

  const AdjustmentPanel({
    super.key,
    required this.params,
    required this.onChanged,
    required this.library,
    required this.onSelectLut,
    required this.onImportLut,
    required this.onDeleteLut,
    this.histogram,
    this.presetBar,
    this.info,
    this.lutName,
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
          if (histogram != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: histogram!,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (info != null) ...[
                  info!,
                  const Divider(height: 1, color: Colors.white12),
                  const SizedBox(height: 4),
                ],
                if (presetBar != null) ...[
                  const SectionLabel(title: 'PRESET'),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    child: presetBar!,
                  ),
                ],
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
                  library: library,
                  onSelect: onSelectLut,
                  onImport: onImportLut,
                  onDelete: onDeleteLut,
                ),
                const SizedBox(height: 8),
                const LocalPanel(),
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
