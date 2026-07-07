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
import 'sections/brush_layer_order_sheet.dart';
import 'sections/preset_section.dart';

/// 退出画笔/智能/主体工具
void _exitLocalTool(WidgetRef ref) {
  ref.read(selectedLocalIdProvider.notifier).set(null);
  final mode = ref.read(brushSettingsProvider).mode;
  if (mode != BrushMode.paint) {
    ref.read(brushSettingsProvider.notifier).setMode(BrushMode.paint);
  }
}

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
  /// Number of non-brush tabs before the brush section begins.
  static const _tabsBeforeBrushes = 8; // light..preset(7) + local(1)

  /// Number of non-brush tabs after the brush section.
  static const _tabsAfterBrushes = 3; // lens, sr, watermark

  int get _totalTabs =>
      _tabsBeforeBrushes + brushManifests.length + _tabsAfterBrushes;
  int get _localTabIndex => 7;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _totalTabs, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index != _localTabIndex) {
      _exitLocalTool(ref);
    }
    // Deactivate any brush whose tab is being left.
    for (int i = 0; i < brushManifests.length; i++) {
      final idx = _tabsBeforeBrushes + i;
      if (_tabController.index != idx) {
        deactivateBrush(brushManifests[i].id, ref);
      }
    }
  }

  Widget _brushSection(DevelopTool tool, AdjustmentParams params) {
    switch (tool) {
      case DevelopTool.spotRemove:
        return SpotRemoveSection(params: params, onChanged: widget.onChanged);
      case DevelopTool.healing:
        return HealingSection(params: params, onChanged: widget.onChanged);
      case DevelopTool.spotHeal:
        return SpotHealSection(params: params, onChanged: widget.onChanged);
      case DevelopTool.dodgeBurn:
        return DodgeBurnSection(params: params, onChanged: widget.onChanged);
      case DevelopTool.sponge:
        return SpongeSection(params: params, onChanged: widget.onChanged);
      default:
        return const SizedBox.shrink();
    }
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

    return Container(
      color: AppColors.panelBg,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.subtleBorder)),
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
                        Tab(text: tr("curve"), height: 36),
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
                  icon: const Icon(Icons.layers, size: 18),
                  tooltip: tr('brushLayerOrder'),
                  onPressed: () => showBrushLayerOrderSheet(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: tr("reset"),
                  onPressed: () => widget.onChanged(AdjustmentParams.neutral),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                  child: LightSection(
                    params: params,
                    onChanged: widget.onChanged,
                  ),
                ),
                SingleChildScrollView(
                  child: WhiteBalanceColorSection(
                    params: params,
                    onChanged: widget.onChanged,
                  ),
                ),
                CurveSection(),
                SingleChildScrollView(
                  child: HslSection(
                    bands: params.hsl,
                    onChanged: (b) => widget.onChanged(params.copyWith(hsl: b)),
                  ),
                ),
                SingleChildScrollView(child: const LutSection()),
                // 以下 4 个 Tab 较重，延迟到首帧结束后构建
                _LazyBuild(
                  builder: (_) => SingleChildScrollView(
                    child: DetailSection(
                      params: params,
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
                _LazyBuild(
                  builder: (_) =>
                      const SingleChildScrollView(child: PresetGrid()),
                ),
                _LazyBuild(
                  builder: (_) =>
                      const SingleChildScrollView(child: LocalPanel()),
                ),
                for (final m in brushManifests)
                  _LazyBuild(
                    builder: (_) => SingleChildScrollView(
                      child: _brushSection(m.tool, params),
                    ),
                  ),
                _LazyBuild(
                  builder: (_) =>
                      const SingleChildScrollView(child: LensSection()),
                ),
                _LazyBuild(
                  builder: (_) => SingleChildScrollView(
                    child: SrSection(
                      params: params,
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
                _LazyBuild(
                  builder: (_) =>
                      const SingleChildScrollView(child: WatermarkSection()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首帧延迟构建：首帧渲染空占位，下一帧真正构建，减少 TabBarView 初始开销
class _LazyBuild extends StatefulWidget {
  final WidgetBuilder builder;
  const _LazyBuild({required this.builder});

  @override
  State<_LazyBuild> createState() => _LazyBuildState();
}

class _LazyBuildState extends State<_LazyBuild> {
  bool _built = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _built = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_built) return const SizedBox.shrink();
    return widget.builder(context);
  }
}
