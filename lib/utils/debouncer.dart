import 'dart:async';

/// 通用防抖器 — 连续调用 [run] 时仅最后一次在 [delay] 后生效
///
/// 典型场景：XMP sidecar 自动保存（500ms 防抖）、历史快照记录（300ms 防抖）
class Debouncer {
  Timer? _timer;

  /// 取消待执行的旧任务，在 [delay] 后执行 [action]
  void run(Duration delay, void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// 取消当前挂起的任务
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 清理定时器，通常在 [Ref.onDispose] 中调用
  void dispose() => cancel();
}

/// 按键分组的防抖器 — 每个 key 独立防抖，适合按文件路径等批量防抖场景
///
/// 典型场景：XMP sidecar 写入（按 rawPath 独立防抖）
class KeyedDebouncer<T> {
  final Duration _delay;
  final Map<T, Timer> _timers = {};

  KeyedDebouncer(this._delay);

  /// 对 [key] 调度防抖执行 [action]；若同一 key 已有挂起任务则重置计时
  void schedule(T key, void Function() action) {
    _timers[key]?.cancel();
    _timers[key] = Timer(_delay, () {
      _timers.remove(key);
      action();
    });
  }

  /// 立即执行 [action] 并取消 [key] 的挂起防抖
  void runNow(T key, void Function() action) {
    _timers[key]?.cancel();
    _timers.remove(key);
    action();
  }

  /// 取消指定 key 的挂起任务
  void cancel(T key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  /// 清理所有挂起任务
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
