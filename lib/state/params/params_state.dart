import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/tethered_shot.dart';
import '../providers.dart';

class CurrentParamsNotifier extends Notifier<AdjustmentParams> {
  @override
  AdjustmentParams build() {
    ref.listen<TetheredShot?>(activeShotProvider, (prev, next) {
      if (next != null && next.path != prev?.path) {
        state = next.params;
      }
    });
    return AdjustmentParams.neutral;
  }

  void update(AdjustmentParams newParams) {
    state = newParams;
    final session = ref.read(tetherSessionNotifierProvider);
    final preserve = ref.read(preserveParamsProvider);
    if (session != null && preserve) {
      ref.read(shotsNotifierProvider.notifier).updateAllParams(newParams);
    } else {
      final active = ref.read(activeShotProvider);
      if (active != null) {
        ref
            .read(shotsNotifierProvider.notifier)
            .updateParams(active.path, newParams);
      }
    }
  }

  void reset() => update(AdjustmentParams.neutral);
}

final currentParamsNotifierProvider =
    NotifierProvider<CurrentParamsNotifier, AdjustmentParams>(
      CurrentParamsNotifier.new,
    );

// ── 对比原片 ──

final compareBypassProvider = StateProvider<bool>((ref) => false);

final effectiveParamsProvider = Provider<AdjustmentParams>((ref) {
  if (ref.watch(compareBypassProvider) ||
      ref.watch(compareViewModeProvider) == CompareViewMode.hold) {
    return AdjustmentParams.neutral;
  }
  return ref.watch(currentParamsNotifierProvider);
});

final effectiveLutEnabledProvider = Provider<bool>((ref) {
  return ref.watch(compareViewModeProvider) != CompareViewMode.hold &&
      !ref.watch(compareBypassProvider);
});

// ── 节流参数（渲染组件专用）──

/// 对 [currentParamsNotifierProvider] 做拖拽感知节流
///
/// - 滑块拖拽中：最多 33ms 更新一次，避免 GPU 过载
/// - 松手瞬间：立刻 flush 最终值，保证精度
///
/// 渲染组件直接 watch 此 provider，无需各自做节流
class _ThrottledParamsNotifier extends Notifier<AdjustmentParams> {
  Timer? _timer;
  DateTime _lastEmit = DateTime(2000);
  bool _isDragging = false;

  static const _interval = Duration(milliseconds: 33);

  @override
  AdjustmentParams build() {
    ref.onDispose(() => _timer?.cancel());

    // 监听拖拽状态
    ref.listen<bool>(isUserDraggingSliderProvider, (prev, next) {
      _isDragging = next;
      if (prev == true && next == false) {
        // 拖拽结束 — 取消定时器，立刻 emit 最新值
        _timer?.cancel();
        _timer = null;
        _lastEmit = DateTime(2000);
        state = ref.read(effectiveParamsProvider);
      }
    });

    // 监听原始参数 — 拖拽中节流，空闲时立即更新
    ref.listen<AdjustmentParams>(effectiveParamsProvider, (prev, next) {
      if (prev == next) return;
      if (!_isDragging) {
        _lastEmit = DateTime(2000);
        state = next;
        return;
      }
      // 拖拽中：节流
      final elapsed = DateTime.now().difference(_lastEmit);
      if (elapsed >= _interval) {
        _lastEmit = DateTime.now();
        state = next;
        return;
      }
      _timer?.cancel();
      _timer = Timer(_interval - elapsed, () {
        _lastEmit = DateTime.now();
        state = next;
      });
    });

    return ref.read(effectiveParamsProvider);
  }
}

final throttledParamsProvider =
    NotifierProvider<_ThrottledParamsNotifier, AdjustmentParams>(
      _ThrottledParamsNotifier.new,
    );
