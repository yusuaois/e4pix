import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../services/lut_library.dart';
import '../state/develop_tool_state.dart';
import 'develop_sections.dart';
import 'local_panel.dart';

class AdjustmentPanel extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  final Widget? histogram;
  final Widget? presetBar;
  final Widget? info;
  final VoidCallback? onEnterCrop;
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
    this.onEnterCrop,
    this.lutName,
  });

  Widget _section(DevelopTool tool) {
    switch (tool) {
      case DevelopTool.light:
        return LightSection(params: params, onChanged: onChanged);
      case DevelopTool.color:
        return WhiteBalanceColorSection(params: params, onChanged: onChanged);
      case DevelopTool.hsl:
        return HslSection(
          bands: params.hsl,
          onChanged: (b) => onChanged(params.copyWith(hsl: b)),
        );
      case DevelopTool.lut:
        return LutSection(
          lutName: lutName,
          intensity: params.lutIntensity,
          onIntensityChanged: (v) =>
              onChanged(params.copyWith(lutIntensity: v)),
          library: library,
          onSelect: onSelectLut,
          onImport: onImportLut,
          onDelete: onDeleteLut,
        );
      case DevelopTool.preset:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(title: 'PRESET'),
            const SizedBox(height: 4),
            if (presetBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: presetBar!,
              ),
          ],
        );
      case DevelopTool.local:
        return const LocalPanel();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(developToolProvider);

    return SizedBox(
      width: 340 + 46,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF14141A),
                border: Border(
                  left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
              child: Column(
                children: [
                  if (histogram != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height / 3,
                      ),
                      child: histogram!,
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      children: [
                        if (info != null) ...[
                          info!,
                          const Divider(height: 1, color: Colors.white12),
                          const SizedBox(height: 4),
                        ],
                        _section(tool),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ToolRail(
            selected: tool,
            onSelect: (t) => ref.read(developToolProvider.notifier).state = t,
            onEnterCrop: onEnterCrop,
            onReset: () => onChanged(AdjustmentParams.neutral),
          ),
        ],
      ),
    );
  }
}

class _ToolRail extends StatelessWidget {
  final DevelopTool selected;
  final ValueChanged<DevelopTool> onSelect;
  final VoidCallback? onEnterCrop;
  final VoidCallback onReset;
  const _ToolRail({
    required this.selected,
    required this.onSelect,
    this.onEnterCrop,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF101015),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _RailItem(
              icon: Icons.light_mode_outlined,
              tooltip: tr('light'),
              selected: selected == DevelopTool.light,
              onTap: () => onSelect(DevelopTool.light),
            ),
            _RailItem(
              icon: Icons.palette_outlined,
              tooltip: tr('color'),
              selected: selected == DevelopTool.color,
              onTap: () => onSelect(DevelopTool.color),
            ),
            _RailItem(
              icon: Icons.gradient,
              tooltip: tr('hsl'),
              selected: selected == DevelopTool.hsl,
              onTap: () => onSelect(DevelopTool.hsl),
            ),
            _RailItem(
              icon: Icons.view_in_ar_outlined,
              tooltip: 'LUT',
              selected: selected == DevelopTool.lut,
              onTap: () => onSelect(DevelopTool.lut),
            ),
            _RailItem(
              icon: Icons.bookmarks_outlined,
              tooltip: tr('preset'),
              selected: selected == DevelopTool.preset,
              onTap: () => onSelect(DevelopTool.preset),
            ),
            _RailItem(
              icon: Icons.brush_outlined,
              tooltip: tr('local'),
              selected: selected == DevelopTool.local,
              onTap: () => onSelect(DevelopTool.local),
            ),
            if (onEnterCrop != null) ...[
              const Divider(
                height: 14,
                indent: 10,
                endIndent: 10,
                color: Colors.white12,
              ),
              _RailItem(
                icon: Icons.crop,
                tooltip: tr('crop'),
                onTap: onEnterCrop!,
              ),
              _RailItem(
                icon: Icons.refresh,
                tooltip: tr("reset"),
                onTap: onReset,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFF6B5BFF)
        : Colors.white.withValues(alpha: 0.6);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF6B5BFF).withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? const Color(0xFF6B5BFF) : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
