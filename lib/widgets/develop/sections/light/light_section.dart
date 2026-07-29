import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/adjustment_params.dart';
import '../../../../state/providers.dart';
import '../shared.dart';
import 'curve_section.dart';

/// 曲线展示模式
enum CurveMode {
  /// 横屏：曲线 inline 嵌入，替换滑块区域
  inline,

  /// 竖屏：曲线以浮层 overlay 展示
  overlay,
}

class LightSection extends ConsumerStatefulWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  final CurveMode curveMode;

  const LightSection({
    super.key,
    required this.params,
    required this.onChanged,
    required this.curveMode,
  });

  @override
  ConsumerState<LightSection> createState() => _LightSectionState();
}

class _LightSectionState extends ConsumerState<LightSection> {
  bool _showCurve = false;

  void _enterCurve() {
    if (widget.curveMode == CurveMode.inline) {
      // 横屏：inline 嵌入曲线面板，进入前自动收起柱状图
      if (!ref.read(histogramCollapsedProvider)) {
        ref.read(histogramCollapsedProvider.notifier).toggle();
      }
      setState(() => _showCurve = true);
    } else {
      // 竖屏：打开浮层 overlay
      ref
          .read(activeOverlayProvider.notifier)
          .open(const CurveActiveOverlay(channel: 0));
    }
  }

  void _exitCurve() {
    setState(() => _showCurve = false);
    // 离开曲线时恢复柱状图（仅 inline 模式）
    ref.read(histogramCollapsedProvider.notifier).show();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.params;

    if (_showCurve) {
      return CurveSection(onDone: _exitCurve);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            title: 'Light',
            trailing: IconButton(
              icon: const Icon(Icons.show_chart, size: 18),
              tooltip: tr('curve'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: _enterCurve,
            ),
          ),
          _buildSliders(p),
        ],
      ),
    );
  }

  Widget _buildSliders(AdjustmentParams p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DevelopSliderTile(
          label: tr("exposure"),
          value: p.exposure,
          min: -5,
          max: 5,
          onChanged: (v) => widget.onChanged(p.copyWith(exposure: v)),
          suffix: ' EV',
          fractionDigits: 2,
        ),
        DevelopSliderTile(
          label: tr("contrast"),
          value: p.contrast,
          min: -100,
          max: 100,
          onChanged: (v) => widget.onChanged(p.copyWith(contrast: v)),
        ),
        DevelopSliderTile(
          label: tr("highlight"),
          value: p.highlights,
          min: -100,
          max: 100,
          onChanged: (v) => widget.onChanged(p.copyWith(highlights: v)),
        ),
        DevelopSliderTile(
          label: tr("shadow"),
          value: p.shadows,
          min: -100,
          max: 100,
          onChanged: (v) => widget.onChanged(p.copyWith(shadows: v)),
        ),
        DevelopSliderTile(
          label: tr("white"),
          value: p.whites,
          min: -100,
          max: 100,
          onChanged: (v) => widget.onChanged(p.copyWith(whites: v)),
        ),
        DevelopSliderTile(
          label: tr("black"),
          value: p.blacks,
          min: -100,
          max: 100,
          onChanged: (v) => widget.onChanged(p.copyWith(blacks: v)),
        ),
      ],
    );
  }
}
