import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brushes/brush_manifest.dart';
import '../../brushes/shared/brush_deactivate.dart';
import '../../core/models/adjustment_params.dart';
import '../../state/providers.dart';
import 'develop_sections.dart';

class HorizontalAdjustmentPanel extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  final Widget? histogramInfoCombo;
  final Widget? presetBar;
  final VoidCallback? onCurveDone;

  const HorizontalAdjustmentPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.histogramInfoCombo,
    this.presetBar,
    this.onCurveDone,
  });

  Widget _section(DevelopTool tool, WidgetRef ref) {
    final m = manifestForTool(tool);
    if (m != null) {
      return m.sectionFactory(params, onChanged);
    }
    switch (tool) {
      case DevelopTool.light:
        return LightSection(
          params: params,
          onChanged: onChanged,
          curveMode: CurveMode.inline,
        );
      case DevelopTool.color:
        return WhiteBalanceColorSection(params: params, onChanged: onChanged);
      case DevelopTool.curve:
        return CurveSection(onDone: onCurveDone);
      case DevelopTool.hsl:
        return HslSection(
          bands: params.hsl,
          onChanged: (b) => onChanged(params.copyWith(hsl: b)),
        );
      case DevelopTool.lut:
        return const LutSection();
      case DevelopTool.detail:
        return DetailSection(params: params, onChanged: onChanged);
      case DevelopTool.preset:
        return const PresetGrid();
      case DevelopTool.local:
        return const LocalPanel();
      case DevelopTool.watermark:
        return const WatermarkSection();
      case DevelopTool.lens:
        return const LensSection();
      case DevelopTool.sr:
        return SrSection(params: params, onChanged: onChanged);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(developToolProvider);

    ref.listen(developToolProvider, (prev, next) {
      exitToolOnChange(ref, prev: prev, next: next);
    });

    return SizedBox(
      width: 340,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Column(
                children: [
                  if (histogramInfoCombo != null) ...[
                    histogramInfoCombo!,
                    // 收起按钮
                    SizedBox(
                      height: 18,
                      child: Center(
                        child: IconButton(
                          icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                          tooltip: tr('collapse'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 18,
                          ),
                          onPressed: () => ref
                              .read(histogramCollapsedProvider.notifier)
                              .toggle(),
                        ),
                      ),
                    ),
                  ] else
                    // 展开按钮
                    SizedBox(
                      height: 18,
                      child: Center(
                        child: IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                          tooltip: tr('expand'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 18,
                          ),
                          onPressed: () => ref
                              .read(histogramCollapsedProvider.notifier)
                              .toggle(),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      child: _section(tool, ref),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ToolRail(
            selected: tool,
            onSelect: (t) => ref.read(developToolProvider.notifier).set(t),
            onReset: () => onChanged(AdjustmentParams.neutral),
          ),
        ],
      ),
    );
  }
}

class _ToolRail extends ConsumerWidget {
  final DevelopTool selected;
  final ValueChanged<DevelopTool> onSelect;
  final VoidCallback onReset;
  const _ToolRail({
    required this.selected,
    required this.onSelect,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 46,
      decoration: const BoxDecoration(color: AppColors.surfaceBg),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // 固定顶部：历史 / reset
          _RailItem(
            icon: Icons.history,
            tooltip: tr('history'),
            onTap: () => showHistoryPanelSheet(context, ref),
          ),
          _RailItem(icon: Icons.refresh, tooltip: tr("reset"), onTap: onReset),
          Divider(
            height: 14,
            indent: 10,
            endIndent: 10,
            color: AppColors.faintBorder,
          ),
          // 可滚动 develop 工具区
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
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
                    icon: Icons.deblur,
                    tooltip: tr('detail'),
                    selected: selected == DevelopTool.detail,
                    onTap: () => onSelect(DevelopTool.detail),
                  ),
                  _RailItem(
                    icon: Icons.brush_outlined,
                    tooltip: tr('local'),
                    selected: selected == DevelopTool.local,
                    onTap: () => onSelect(DevelopTool.local),
                  ),
                  for (final m in brushManifests)
                    _RailItem(
                      icon: m.icon,
                      tooltip: tr(m.titleKey),
                      selected: selected == m.tool,
                      onTap: () => onSelect(m.tool),
                    ),
                  _RailItem(
                    icon: Icons.camera_outlined,
                    tooltip: tr('lens'),
                    selected: selected == DevelopTool.lens,
                    onTap: () => onSelect(DevelopTool.lens),
                  ),
                  _RailItem(
                    icon: Icons.auto_awesome,
                    tooltip: tr('superResolution'),
                    selected: selected == DevelopTool.sr,
                    onTap: () => onSelect(DevelopTool.sr),
                  ),
                  _RailItem(
                    icon: Icons.border_style,
                    tooltip: tr('watermark'),
                    selected: selected == DevelopTool.watermark,
                    onTap: () => onSelect(DevelopTool.watermark),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
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
        ? Theme.of(context).colorScheme.primary
        : AppColors.mediumText;
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
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
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
