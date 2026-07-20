import 'dart:async';

/// 通用节流器 — 首次调用启动固定间隔定时器，期间后续调用仅更新 pending 值
///
/// 与 [Debouncer] 的区别：
/// - Debouncer：每次调用重置计时，连续调用期间不触发，最后一次调用后 [delay] 才执行
/// - Throttler：首次调用启动定时器，固定 [interval] 后取最后一次的 pending 值执行
///
/// 典型场景：拖拽中 30fps 限频渲染
class Throttler<T> {
  final Duration _interval;
  Timer? _timer;
  T? _pending;

  Throttler({Duration interval = const Duration(milliseconds: 33)})
    : _interval = interval;

  /// 节流提交：[interval] 内多次调用只取最后一次的 [value]
  void throttle(T value, void Function(T) commit) {
    _pending = value;
    if (_timer != null) return;
    _timer = Timer(_interval, () {
      _timer = null;
      final c = _pending;
      if (c != null) {
        _pending = null;
        commit(c);
      }
    });
  }

  /// 立即提交当前 pending 值并取消定时器
  void flush(void Function(T) commit) {
    _timer?.cancel();
    _timer = null;
    final c = _pending;
    if (c != null) {
      _pending = null;
      commit(c);
    }
  }

  /// 取消当前定时器并丢弃 pending
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  /// 清理资源
  void dispose() => cancel();
}
