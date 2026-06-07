import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../state/providers.dart';
import 'develop_sections.dart';
import '../local/local_panel.dart';
import 'preset_bar.dart';

/// 手机布局下的底部工具面板（7 个 Tab 页）
class VerticalAdjustmentPanel extends ConsumerWidget {
  final ValueChanged<AdjustmentParams> onChanged;
  const VerticalAdjustmentPanel({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ref.watch(currentParamsNotifierProvider);

    return SizedBox(
      height: 320,
      child: DefaultTabController(
        length: 7,
        child: Container(
          color: const Color(0xFF14141A),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        labelPadding: EdgeInsets.zero,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: const TextStyle(fontSize: 11),
                        tabs: [
                          Tab(text: tr("light"), height: 36),
                          Tab(text: tr("color"), height: 36),
                          Tab(text: tr("hsl"), height: 36),
                          Tab(text: 'LUT', height: 36),
                          Tab(text: tr('detail'), height: 36),
                          Tab(text: tr("preset"), height: 36),
                          Tab(text: tr("local"), height: 36),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: tr("reset"),
                      onPressed: () => onChanged(AdjustmentParams.neutral),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      child: LightSection(params: params, onChanged: onChanged),
                    ),
                    SingleChildScrollView(
                      child: WhiteBalanceColorSection(
                        params: params,
                        onChanged: onChanged,
                      ),
                    ),
                    SingleChildScrollView(
                      child: HslSection(
                        bands: params.hsl,
                        onChanged: (b) => onChanged(params.copyWith(hsl: b)),
                      ),
                    ),
                    SingleChildScrollView(child: const LutSection()),
                    SingleChildScrollView(
                      child: DetailSection(
                        params: params,
                        onChanged: onChanged,
                      ),
                    ),
                    const SingleChildScrollView(child: PresetGrid()),
                    const SingleChildScrollView(child: LocalPanel()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
