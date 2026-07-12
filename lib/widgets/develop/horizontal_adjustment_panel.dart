import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brushes/brush_manifest.dart';
import '../../brushes/shared/brush_deactivate.dart';
import '../../core/models/adjustment_params.dart';
import '../../state/providers.dart';
import 'develop_sections.dart';
import 'sections/history_panel_sheet.dart';
import 'sections/preset_section.dart';

/// 退出画笔/智能/主体工具
void _exitLocalTool(WidgetRef ref) {
  ref.read(selectedLocalIdProvider.notifier).set(null);
  final mode = ref.read(brushSettingsProvider).mode;
  if (mode != BrushMode.paint) {
    ref.read(brushSettingsProvider.notifier).setMode(BrushMode.paint);
  }
}

class HorizontalAdjustmentPanel extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  final Widget? histogram;
  final Widget? presetBar;
  final Widget? info;
  final VoidCallback? onEnterCrop;

  const HorizontalAdjustmentPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.histogram,
    this.presetBar,
    this.info,
    this.onEnterCrop,
  });

  Widget _section(DevelopTool tool) {
    final m = manifestForTool(tool);
    if (m != null) return m.sectionFactory(params, onChanged);
    switch (tool) {
      case DevelopTool.light:
        return LightSection(params: params, onChanged: onChanged);
      case DevelopTool.color:
        return WhiteBalanceColorSection(params: params, onChanged: onChanged);
      case DevelopTool.curve:
        return const CurveSection();
      case DevelopTool.hsl:
        return HslSection(
          bands: params.hsl,
          onChanged: (b) => onChanged(params.copyWith(hsl: b)),
        );
      case DevelopTool.lut:
        return LutSection();
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
      case DevelopTool.info:
        return info ?? const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(developToolProvider);

    // 切离 local 时退出画笔/智能/主体工具
    ref.listen(developToolProvider, (prev, next) {
      if (prev == DevelopTool.local && next != DevelopTool.local) {
        _exitLocalTool(ref);
      }
    });
    // 切离任意画笔工具时通过 manifest 自动退出
    for (final m in brushManifests) {
      ref.listen(developToolProvider, (prev, next) {
        if (prev == m.tool && next != m.tool) {
          deactivateBrush(m.id, ref);
        }
      });
    }

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
                      children: [_section(tool)],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ToolRail(
            selected: tool,
            onSelect: (t) => ref.read(developToolProvider.notifier).set(t),
            onEnterCrop: onEnterCrop,
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
  final VoidCallback? onEnterCrop;
  final VoidCallback onReset;
  const _ToolRail({
    required this.selected,
    required this.onSelect,
    this.onEnterCrop,
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
          // 固定顶部：info / crop / 图层 / 历史 / reset
          _RailItem(
            icon: Icons.info_outline,
            tooltip: tr('info'),
            selected: selected == DevelopTool.info,
            onTap: () => onSelect(DevelopTool.info),
          ),
          if (onEnterCrop != null)
            _RailItem(
              icon: Icons.crop,
              tooltip: tr('crop'),
              onTap: onEnterCrop!,
            ),
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
                    icon: Icons.show_chart,
                    tooltip: tr('curve'),
                    selected: selected == DevelopTool.curve,
                    onTap: () => onSelect(DevelopTool.curve),
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
