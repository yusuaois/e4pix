import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/tethered_shot.dart';
import '../../utils/debouncer.dart';
import '../providers.dart';

class CurrentParamsNotifier extends Notifier<AdjustmentParams> {
  @override
  AdjustmentParams build() {
    ref.listen<TetheredShot?>(activeShotProvider, (prev, next) {
      if (next != null && next.path != prev?.path) {
        // 切图：直接设置 state，不触发 userEditVersion
        state = next.params;
      }
    });
    return AdjustmentParams.neutral;
  }

  void update(AdjustmentParams newParams) {
    state = newParams;
    // 用户编辑：递增版本号，历史系统据此区分切图 vs 编辑
    ref.read(userEditVersionProvider.notifier).increment();
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

/// 用户编辑版本号 —— 每次调用 [CurrentParamsNotifier.update] 时递增。
///
/// 切图引起的参数变化不会递增此版本号，历史系统以此区分真实编辑与文件切换。
final userEditVersionProvider =
    NotifierProvider<UserEditVersionNotifier, int>(
      UserEditVersionNotifier.new,
    );

class UserEditVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

final currentParamsNotifierProvider =
    NotifierProvider<CurrentParamsNotifier, AdjustmentParams>(
      CurrentParamsNotifier.new,
    );

// ── 对比原片 ──

class CompareBypassNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final compareBypassProvider = NotifierProvider<CompareBypassNotifier, bool>(
  CompareBypassNotifier.new,
);

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

// ── 防抖参数（渲染组件专用）──

/// 对 [currentParamsNotifierProvider] 做拖拽感知防抖
///
/// - 滑块拖拽中：最多 33ms 更新一次，避免 GPU 过载
/// - 松手瞬间：立刻 flush 最终值，保证精度
///
/// 渲染组件直接 watch 此 provider，无需各自做防抖
class _DebouncedParamsNotifier extends Notifier<AdjustmentParams> {
  final _debouncer = Debouncer();
  DateTime _lastEmit = DateTime(2000);
  bool _isDragging = false;

  static const _interval = Duration(milliseconds: 33);

  @override
  AdjustmentParams build() {
    ref.onDispose(() => _debouncer.dispose());

    // 监听拖拽状态
    ref.listen<bool>(isUserDraggingSliderProvider, (prev, next) {
      _isDragging = next;
      if (prev == true && next == false) {
        // 拖拽结束 — 取消定时器，立刻 emit 最新值
        _debouncer.cancel();
        _lastEmit = DateTime(2000);
        state = ref.read(effectiveParamsProvider);
      }
    });

    // 监听原始参数 — 拖拽中防抖，空闲时立即更新
    ref.listen<AdjustmentParams>(effectiveParamsProvider, (prev, next) {
      if (prev == next) return;
      if (!_isDragging) {
        _lastEmit = DateTime(2000);
        state = next;
        return;
      }
      // 拖拽中：防抖
      final elapsed = DateTime.now().difference(_lastEmit);
      if (elapsed >= _interval) {
        _lastEmit = DateTime.now();
        state = next;
        return;
      }
      _debouncer.run(_interval - elapsed, () {
        _lastEmit = DateTime.now();
        state = next;
      });
    });

    return ref.read(effectiveParamsProvider);
  }
}

final debouncedParamsProvider =
    NotifierProvider<_DebouncedParamsNotifier, AdjustmentParams>(
      _DebouncedParamsNotifier.new,
    );
