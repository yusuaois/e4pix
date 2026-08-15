import 'dart:ui' as ui;

/// 画笔标记型提供者的通用二级渲染缓存
///
/// 一级——标记哈希缓存（参数拖动优化）：
///   key = (developKey, 所有标记的哈希)
///   滑块变化时 develop 输出变化但标记不变 → 缓存命中，该画笔 0 GPU 趟
///
/// 二级——增量滚动缓存（新增笔画优化）：
///   key = (developKey, markCount)
///   develop 参数相同，新增标记 → 从上一索引恢复，O(N) → O(新增标记)
///
/// 缓存失效条件：
///   - 拖动结束：仅一级失效（二级保留用于下一笔画继续）
///   - 源图变更：两级全部失效
///
/// ## 所有权约定
///
/// 每次 [put] 存储克隆，每次 [get] 返回克隆，一趟来回消耗两倍 GPU 拷贝
/// （put 克隆 + get 克隆），换取安全的多缓存命中——同一条目可在参数拖动期间
/// 命中多次，调用方无需关心所有权，从 [get] 获取克隆的调用方拥有它并负责 dispose
///
/// [T] 是标记类型，[computeKey] 从标记列表中提取可哈希的值
class IncrementalRenderCache<T> {
  // ── 一级：标记哈希缓存 ──
  int _marksKey = 0;
  int _marksDevKey = 0;
  ui.Image? _marksResult;

  // ── 二级：增量滚动缓存 ──
  int _rollingDevKey = 0;
  int _rollingCount = 0;
  ui.Image? _rollingResult;

  final int Function(List<T> marks) computeKey;

  IncrementalRenderCache({required this.computeKey});

  /// 一级缓存命中：标记列表不变且 develop 参数不变
  /// 返回克隆，调用方拥有并负责 dispose
  ui.Image? getFromMarksCache(int developKey, List<T> marks) {
    if (marks.isEmpty || _marksResult == null) return null;
    if (developKey != _marksDevKey) return null;
    return computeKey(marks) == _marksKey ? _marksResult?.clone() : null;
  }

  /// 二级缓存命中：返回（中间结果克隆, 已渲染数）
  /// 返回克隆，调用方拥有记录中的 image 并负责 dispose
  (ui.Image, int)? getIncremental(int developKey, List<T> marks) {
    if (_rollingResult == null) return null;
    if (developKey != _rollingDevKey) return null;
    if (_rollingCount == 0 || _rollingCount > marks.length) return null;
    return (_rollingResult!.clone(), _rollingCount);
  }

  /// 存储一级缓存条目，克隆 [result]，调用方保留所有权
  void putMarksCache(int developKey, List<T> marks, ui.Image result) {
    _marksResult?.dispose();
    _marksResult = result.clone();
    _marksKey = computeKey(marks);
    _marksDevKey = developKey;
  }

  /// 存储二级滚动缓存条目，克隆 [result]，调用方保留所有权
  void putRolling(int developKey, int count, ui.Image result) {
    _rollingResult?.dispose();
    _rollingResult = result.clone();
    _rollingDevKey = developKey;
    _rollingCount = count;
  }

  /// 仅使一级失效（拖动结束时调用）
  /// 二级保留——会在 devKey 变化时自动失效
  void invalidateMarksCache() {
    _marksResult?.dispose();
    _marksResult = null;
    _marksKey = 0;
  }

  /// 全部失效（源图变更时）
  void invalidate() {
    _marksResult?.dispose();
    _marksResult = null;
    _marksKey = 0;
    _rollingResult?.dispose();
    _rollingResult = null;
    _rollingDevKey = 0;
    _rollingCount = 0;
  }

  void dispose() => invalidate();
}
