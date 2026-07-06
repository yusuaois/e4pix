import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 对分屏对比模式
enum CompareViewMode { off, hold, split }

/// 对比模式状态管理器
class CompareModeNotifier extends Notifier<CompareViewMode> {
  CompareViewMode _preHoldMode = CompareViewMode.off;

  @override
  CompareViewMode build() {
    return CompareViewMode.off;
  }

  void turnOff() {
    state = CompareViewMode.off;
  }

  /// 切换对比模式
  void toggleSplit() {
    if (state == CompareViewMode.hold) return;
    state = state == CompareViewMode.split
        ? CompareViewMode.off
        : CompareViewMode.split;
  }

  /// 长按开始：记录当前状态，进入 hold 模式
  void startHold() {
    _preHoldMode = state;
    state = CompareViewMode.hold;
  }

  /// 长按结束：恢复之前状态
  void endHold() {
    state = _preHoldMode;
  }
}

final compareViewModeProvider =
    NotifierProvider<CompareModeNotifier, CompareViewMode>(
      CompareModeNotifier.new,
    );

/// 分屏分隔线位置（0.0=最左，1.0=最右）(从 interaction_state 移过来)
class SplitDividerNotifier extends Notifier<double> {
  @override
  double build() => 0.5;
  void set(double v) => state = v;
}

final splitDividerProvider = NotifierProvider<SplitDividerNotifier, double>(
  SplitDividerNotifier.new,
);
