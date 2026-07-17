import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 横屏柱状图是否被用户手动收起
///
/// 未来收起按钮接入后，调用 [toggle] 切换；切离曲线模式时调用 [show] 复位
class HistogramCollapseNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void show() => state = false;
}

final histogramCollapsedProvider =
    NotifierProvider<HistogramCollapseNotifier, bool>(
      HistogramCollapseNotifier.new,
    );

/// 判断柱状图在横屏布局中是否应自动显示（不考虑手动收起）
///
/// 桌面端始终显示；非曲线模式始终显示；曲线模式下剩余高度 >= 420px 时显示
bool shouldShowHistogram(BuildContext context, bool isCurveMode) {
  final platform = Theme.of(context).platform;
  final isDesktop = switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS => false,
    _ => true,
  };
  if (isDesktop) return true;
  if (!isCurveMode) return true;

  // 曲线 section 总高度 ≈ 标题行 + 网格 + 通道 + 提示 ≈ 260px
  // histogram(~120) + curve(~260) + margin ≈ 420
  final availableHeight =
      MediaQuery.of(context).size.height -
      12 -
      12 - // outer padding
      48 -
      12 -
      8 - // top cards
      60; // safe margin
  return availableHeight >= 420;
}
