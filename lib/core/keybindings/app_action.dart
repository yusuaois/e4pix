import 'package:flutter/services.dart';

String keyDisplayName(LogicalKeyboardKey? k) {
  if (k == null) return '—';
  // 特殊键映射
  const special = {0x00000020: 'Space'};
  if (k == LogicalKeyboardKey.backslash) return '\\';
  if (k == LogicalKeyboardKey.slash) return '/';
  if (k == LogicalKeyboardKey.f11) return 'F11';
  if (k == LogicalKeyboardKey.space) return 'Space';
  if (k == LogicalKeyboardKey.tab) return 'Tab';
  if (special.containsKey(k.keyId)) return special[k.keyId]!;
  if (k.keyLabel.isNotEmpty) return k.keyLabel.toUpperCase();
  return k.debugName ?? 'Key';
}

/// 可自定义的快捷动作（单键 / hold 型）
/// 不含 Ctrl 组合键（撤销/重做）和上下文键（裁剪 Esc/Enter、全屏 Esc）
enum AppAction {
  toggleFullscreen,
  compareHold, // hold 型：按下生效、松开恢复
  samplingHold, // hold 型：污点修复取样模式
  enterCrop,
  rate0,
  rate1,
  rate2,
  rate3,
  rate4,
  rate5,
  flagPick,
  flagReject,
  nextImage,
  prevImage,
}

extension AppActionMeta on AppAction {
  /// 是否 hold 型
  bool get isHold =>
      this == AppAction.compareHold || this == AppAction.samplingHold;

  /// 可读标签 key
  String get labelKey => switch (this) {
    AppAction.toggleFullscreen => 'keyActFullscreen',
    AppAction.compareHold => 'keyActCompare',
    AppAction.samplingHold => 'keyActSampling',
    AppAction.enterCrop => 'keyActCrop',
    AppAction.rate0 => 'keyActRate0',
    AppAction.rate1 => 'keyActRate1',
    AppAction.rate2 => 'keyActRate2',
    AppAction.rate3 => 'keyActRate3',
    AppAction.rate4 => 'keyActRate4',
    AppAction.rate5 => 'keyActRate5',
    AppAction.flagPick => 'keyActFlagPick',
    AppAction.flagReject => 'keyActFlagReject',
    AppAction.nextImage => 'keyActNextImage',
    AppAction.prevImage => 'keyActPrevImage',
  };
}

/// 默认键绑定
const Map<AppAction, LogicalKeyboardKey> kDefaultBindings = {
  AppAction.toggleFullscreen: LogicalKeyboardKey.f11,
  AppAction.compareHold: LogicalKeyboardKey.backslash,
  AppAction.samplingHold: LogicalKeyboardKey.altLeft,
  AppAction.enterCrop: LogicalKeyboardKey.keyR,
  AppAction.rate0: LogicalKeyboardKey.digit0,
  AppAction.rate1: LogicalKeyboardKey.digit1,
  AppAction.rate2: LogicalKeyboardKey.digit2,
  AppAction.rate3: LogicalKeyboardKey.digit3,
  AppAction.rate4: LogicalKeyboardKey.digit4,
  AppAction.rate5: LogicalKeyboardKey.digit5,
  AppAction.flagPick: LogicalKeyboardKey.keyP,
  AppAction.flagReject: LogicalKeyboardKey.keyX,
  AppAction.nextImage: LogicalKeyboardKey.arrowDown,
  AppAction.prevImage: LogicalKeyboardKey.arrowUp,
};
