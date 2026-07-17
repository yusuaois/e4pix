import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brushes/brush_manifest.dart';
import '../../brushes/shared/brush_deactivate.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';
import 'develop_sections.dart';
import 'sections/history_panel_sheet.dart';
import 'sections/preset/preset_section.dart';

/// 手机布局下的底部工具面板
class VerticalAdjustmentPanel extends ConsumerStatefulWidget {
  final ValueChanged<AdjustmentParams> onChanged;
  const VerticalAdjustmentPanel({super.key, required this.onChanged});

  @override
  ConsumerState<VerticalAdjustmentPanel> createState() =>
      _VerticalAdjustmentPanelState();
}

class _VerticalAdjustmentPanelState
    extends ConsumerState<VerticalAdjustmentPanel>
    with TickerProviderStateMixin {
  late final List<DevelopTool> _toolOrder = [
    DevelopTool.light,
    DevelopTool.color,
    DevelopTool.hsl,
    DevelopTool.lut,
    DevelopTool.detail,
    DevelopTool.preset,
    DevelopTool.local,
    for (final m in brushManifests) m.tool,
    DevelopTool.lens,
    DevelopTool.sr,
    DevelopTool.watermark,
  ];

  int get _totalTabs => _toolOrder.length;

  late final TabController _tabController;
  int _prevIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _totalTabs, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final prev = _toolForIndex(_prevIndex);
    final next = _toolForIndex(_tabController.index);
    exitToolOnChange(ref, prev: prev, next: next);
    _prevIndex = _tabController.index;
  }

  DevelopTool _toolForIndex(int index) => _toolOrder[index];

  Widget _brushSection(DevelopTool tool, AdjustmentParams params) {
    final m = manifestForTool(tool);
    return m?.sectionFactory(params, widget.onChanged) ??
        const SizedBox.shrink();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(currentParamsNotifierProvider);
    final overlay = ref.watch(activeOverlayProvider);
    final microBar = overlay.buildMicroBar(
      context,
      () => ref.read(activeOverlayProvider.notifier).close(),
    );

    return Container(
      color: AppColors.panelBg,
      child: Column(
        children: [
          if (microBar != null)
            microBar
          else
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.subtleBorder),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MediaQuery.removePadding(
                      context: context,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorSize: TabBarIndicatorSize.label,
                        labelStyle: AppTypography.bodySmall,
                        labelColor: AppColors.textPrimary,
                        unselectedLabelColor: AppColors.textTertiary,
                        tabs: [
                          Tab(text: tr("light"), height: 36),
                          Tab(text: tr("color"), height: 36),
                          Tab(text: tr("hsl"), height: 36),
                          Tab(text: 'LUT', height: 36),
                          Tab(text: tr('detail'), height: 36),
                          Tab(text: tr("preset"), height: 36),
                          Tab(text: tr("local"), height: 36),
                          for (final m in brushManifests)
                            Tab(text: tr(m.titleKey), height: 36),
                          Tab(text: tr("lens"), height: 36),
                          Tab(text: tr('superResolution'), height: 36),
                          Tab(text: tr("watermark"), height: 36),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.history, size: 18),
                    tooltip: tr('history'),
                    onPressed: () => showHistoryPanelSheet(context, ref),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: tr("reset"),
                    onPressed: () => widget.onChanged(AdjustmentParams.neutral),
                  ),
                ],
              ),
            ),
          if (microBar != null)
            const Expanded(child: SizedBox.shrink())
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  LightSection(
                    params: params,
                    onChanged: widget.onChanged,
                    curveMode: CurveMode.overlay,
                  ),
                  WhiteBalanceColorSection(
                    params: params,
                    onChanged: widget.onChanged,
                  ),
                  HslSection(
                    bands: params.hsl,
                    onChanged: (b) => widget.onChanged(params.copyWith(hsl: b)),
                  ),
                  const LutSection(),
                  // 以下 Tab 较重，延迟到首帧结束后构建
                  LazyBuild(
                    builder: (_) => DetailSection(
                      params: params,
                      onChanged: widget.onChanged,
                    ),
                  ),
                  LazyBuild(builder: (_) => const PresetGrid()),
                  LazyBuild(builder: (_) => const LocalPanel()),
                  for (final m in brushManifests)
                    LazyBuild(builder: (_) => _brushSection(m.tool, params)),
                  LazyBuild(builder: (_) => const LensSection()),
                  LazyBuild(
                    builder: (_) =>
                        SrSection(params: params, onChanged: widget.onChanged),
                  ),
                  LazyBuild(builder: (_) => const WatermarkSection()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
