import 'dart:ui';

/// 公共画笔路径追踪器
///
/// 累积拖拽原始点，沿路径按固定间距生成均匀采样位置。
/// 适用于任何需要"沿拖拽路径等距放置标记"的场景（污点修复、局部调整等）。
///
/// 用法：
/// ```dart
/// final tracker = PathBrushTracker(spacing: 0.005);
/// tracker.start(firstPoint);
/// // 拖拽中：
/// for (final pos in tracker.move(nextPoint)) {
///   placeMarker(pos);
/// }
/// // 拖拽结束：
/// tracker.end();
/// ```
class PathBrushTracker {
  /// 采样间距（归一化坐标）
  final double spacing;

  List<Offset> _points = [];
  double _walked = 0;

  PathBrushTracker({required this.spacing});

  /// 当前已累积的全部原始点
  List<Offset> get points => _points;

  /// 开始新的笔触
  void start(Offset point) {
    _points = [point];
    _walked = 0;
  }

  /// 追加拖拽点，返回新生成的均匀采样位置
  ///
  /// 内部累积所有原始点（与 local 画笔一致，不过滤），
  /// 沿折线路径按 [spacing] 间距提取新位置。
  List<Offset> move(Offset point) {
    if (_points.isEmpty) return const [];
    _points.add(point);
    return _extract();
  }

  /// 结束笔触，返回剩余路径上的采样点
  List<Offset> end() {
    final remaining = _extractRemaining();
    _points = [];
    _walked = 0;
    return remaining;
  }

  List<Offset> _extract() {
    final result = <Offset>[];
    while (true) {
      final next = _walkOne();
      if (next == null) break;
      result.add(next);
    }
    return result;
  }

  List<Offset> _extractRemaining() {
    // 沿剩余路径每隔 spacing 取点，最后一个点一定取到
    final result = <Offset>[];
    while (true) {
      final next = _walkOne();
      if (next == null) break;
      result.add(next);
    }
    // 保证终点被覆盖
    if (_points.length >= 2) {
      final last = _points.last;
      if (result.isEmpty || (result.last - last).distance > 1e-6) {
        result.add(last);
      }
    }
    return result;
  }

  /// 沿折线前进一个 spacing，返回采样位置；无法前进则返回 null
  Offset? _walkOne() {
    final pts = _points;
    final len = pts.length;
    if (len < 2) return null;

    final target = _walked + spacing;

    // 沿段累积距离
    double accumulated = 0;
    for (int i = 0; i < len - 1; i++) {
      final segLen = (pts[i + 1] - pts[i]).distance;
      if (accumulated + segLen < target) {
        accumulated += segLen;
        continue;
      }
      // 目标落在此段内
      final remain = target - accumulated;
      final t = segLen > 1e-10 ? remain / segLen : 0.0;
      final pos = Offset(
        pts[i].dx + (pts[i + 1].dx - pts[i].dx) * t,
        pts[i].dy + (pts[i + 1].dy - pts[i].dy) * t,
      );
      _walked = target;
      return pos;
    }
    return null;
  }
}
