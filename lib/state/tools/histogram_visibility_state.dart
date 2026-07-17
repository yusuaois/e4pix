import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 横屏柱状图是否被用户手动收起
///
/// 调用 [toggle] 切换；切离曲线模式时调用 [show] 复位
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
