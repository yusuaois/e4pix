import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_action.dart';
import '../models/tethered_shot.dart';
import '../../state/providers.dart';

/// 处理 develop 界面的键盘事件，从 [DevelopScreen] 的 build 中调用：
/// ```dart
/// Focus(onKeyEvent: (_, e) => handleDevelopKeyEvent(ref, e, keys))
/// ```
KeyEventResult handleDevelopKeyEvent(
  WidgetRef ref,
  KeyEvent event,
  KeybindingState keys,
) {
  final ctrl =
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  // Ctrl+Z / Ctrl+Shift+Z
  if (event is KeyDownEvent &&
      ctrl &&
      event.logicalKey == LogicalKeyboardKey.keyZ) {
    final n = ref.read(historyNotifierProvider.notifier);
    HardwareKeyboard.instance.isShiftPressed ? n.redo() : n.undo();
    return KeyEventResult.handled;
  }

  final inCrop = ref.read(cropEditModeProvider);

  // Esc/Enter in crop mode
  if (inCrop && event is KeyDownEvent) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      cancelCrop(ref);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      commitCrop(ref);
      return KeyEventResult.handled;
    }
  }

  // 自定义动作
  final action = keys.actionFor(event.logicalKey);
  if (action == null) return KeyEventResult.ignored;

  // hold 型动作允许修饰键（如 Alt 用于 samplingHold）
  // 其他动作在有修饰键时不响应
  if (!action.isHold &&
      (ctrl ||
          HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isAltPressed)) {
    return KeyEventResult.ignored;
  }

  return _handleAction(ref, action, event, inCrop);
}

KeyEventResult _handleAction(
  WidgetRef ref,
  AppAction action,
  KeyEvent event,
  bool inCrop,
) {
  // hold：down 设 true、up 设 false
  if (action == AppAction.compareHold) {
    if (event is KeyDownEvent) {
      ref.read(compareBypassProvider.notifier).state = true;
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      ref.read(compareBypassProvider.notifier).state = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // sampling hold：down 设 true、up 设 false
  if (action == AppAction.samplingHold) {
    if (event is KeyDownEvent) {
      ref.read(samplingHoldProvider.notifier).state = true;
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      ref.read(samplingHoldProvider.notifier).state = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  if (event is! KeyDownEvent) return KeyEventResult.ignored;

  switch (action) {
    case AppAction.toggleFullscreen:
      final cur = ref.read(fullscreenPreviewProvider);
      ref.read(fullscreenPreviewProvider.notifier).state = !cur;
      return KeyEventResult.handled;

    case AppAction.enterCrop:
      if (!inCrop) {
        enterCropMode(ref);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;

    case AppAction.rate0:
    case AppAction.rate1:
    case AppAction.rate2:
    case AppAction.rate3:
    case AppAction.rate4:
    case AppAction.rate5:
      if (inCrop) return KeyEventResult.ignored;
      final activePath = ref.read(activeShotPathProvider);
      if (activePath == null) return KeyEventResult.ignored;
      final rating = action.index - AppAction.rate0.index;
      ref.read(shotsNotifierProvider.notifier).updateRating(activePath, rating);
      _writeSidecarNow(ref, activePath);
      return KeyEventResult.handled;

    case AppAction.flagPick:
      if (inCrop) return KeyEventResult.ignored;
      return _toggleFlag(ref, ShotFlag.pick);

    case AppAction.flagReject:
      if (inCrop) return KeyEventResult.ignored;
      return _toggleFlag(ref, ShotFlag.reject);

    case AppAction.nextImage:
      if (inCrop) return KeyEventResult.ignored;
      return _switchImage(ref, 1);

    case AppAction.prevImage:
      if (inCrop) return KeyEventResult.ignored;
      return _switchImage(ref, -1);

    case AppAction.compareHold:
    case AppAction.samplingHold:
      return KeyEventResult.ignored;
  }
}

KeyEventResult _switchImage(WidgetRef ref, int delta) {
  final shots = ref.read(shotsNotifierProvider);
  if (shots.isEmpty) return KeyEventResult.ignored;
  final activePath = ref.read(activeShotPathProvider);
  if (activePath == null) {
    // 无选中图时选第一张
    ref.read(selectShotProvider)(shots.first);
    return KeyEventResult.handled;
  }
  final idx = shots.indexWhere((s) => s.path == activePath);
  if (idx < 0) return KeyEventResult.ignored;
  final nextIdx = (idx + delta) % shots.length;
  ref.read(selectShotProvider)(shots[nextIdx]);
  return KeyEventResult.handled;
}

KeyEventResult _toggleFlag(WidgetRef ref, ShotFlag flag) {
  final active = ref.read(activeShotPathProvider);
  if (active == null) return KeyEventResult.ignored;
  final cur = ref.read(activeShotProvider);
  final next = cur?.flag == flag ? ShotFlag.none : flag;
  ref.read(shotsNotifierProvider.notifier).updateFlag(active, next);
  _writeSidecarNow(ref, active);
  return KeyEventResult.handled;
}

/// 立即将指定图片的 params/rating/flag 写入 sidecar
void _writeSidecarNow(WidgetRef ref, String path) {
  if (!ref.read(sidecarEnabledProvider)) return;
  final shots = ref.read(shotsNotifierProvider);
  final idx = shots.indexWhere((s) => s.path == path);
  if (idx < 0) return;
  final s = shots[idx];
  ref.read(sidecarWriterProvider).writeNow(path, s.params, s.rating, s.flag);
}
