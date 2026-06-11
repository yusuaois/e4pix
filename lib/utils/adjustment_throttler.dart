import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debouncer.dart';
import '../../state/interaction_state.dart';

/// 滑块拖拽期间的节流工具
///
/// 封装 isUserDraggingSliderProvider 监听 + 拖拽期间延迟节流 + 拖拽结束后刷新
class AdjustmentThrottler {
  final WidgetRef ref;
  final _throttler = Throttler();
  ProviderSubscription<bool>? _dragSub;

  AdjustmentThrottler(this.ref);

  /// 开始监听拖拽状态，传入拖拽结束时需执行的回调
  void listen({required VoidCallback onDragEnd}) {
    _dragSub = ref.listenManual<bool>(isUserDraggingSliderProvider, (
      prev,
      next,
    ) {
      if (prev == true && next == false) {
        _throttler.cancel();
        onDragEnd();
      }
    });
  }

  /// 按当前拖拽状态节流执行 [action]
  /// 拖拽中延迟 50ms，空闲时延迟 33ms（或由 [dragDelay] 指定）
  void throttle(VoidCallback action, {Duration? dragDelay}) {
    final isDragging = ref.read(isUserDraggingSliderProvider);
    final delay = dragDelay ?? Duration(milliseconds: isDragging ? 50 : 33);
    _throttler.run(delay, action);
  }

  void dispose() {
    _throttler.dispose();
    _dragSub?.close();
  }
}
