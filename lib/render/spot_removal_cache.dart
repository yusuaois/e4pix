import 'dart:ui' as ui;

import '../core/models/spot_mark.dart';

/// Spot removal 结果缓存（两级）
///
/// 第一级 — Spots hash 缓存（参数拖动期间复用）
///   key = Object.hashAll(spots.hashCode)
///   参数滑块变化 → develop 输出变化，但 spots 不变 → 缓存命中，0 个 GPU pass
///
/// 第二级 — 增量滚动缓存（新描边只跑新增 spots）
///   key = (developKey, spotCount)
///   同一组 develop 参数下新增更多 spots → 从上次中断的 index 继续渲染
///   O(N) → O(新增数)
///
/// 缓存失效条件：
///   - 参数变化拖完：只失效 spots hash 缓存（保留增量缓存供新描边使用）
///   - 切图：全部失效
class SpotRemovalCache {
  // ── 第一级：Spots hash 缓存（参数拖动期间用）──
  int _spotsKey = 0;
  ui.Image? _spotsResult;

  // ── 第二级：增量滚动缓存（新增描边用）──
  int _rollingDevKey = 0;
  int _rollingSpotCount = 0;
  ui.Image? _rollingResult;

  static int computeSpotsKey(List<SpotMark> spots) =>
      Object.hashAll(spots.map((s) => s.hashCode));

  /// 第一级缓存命中：spots 列表未变（参数拖动期间）
  /// 返回 clone，调用方拥有所有权，无需再 clone
  ui.Image? getFromSpotsCache(List<SpotMark> spots) {
    if (spots.isEmpty || _spotsResult == null) return null;
    return computeSpotsKey(spots) == _spotsKey ? _spotsResult?.clone() : null;
  }

  /// 第二级缓存命中：返回 (中间结果 clone, 已渲染到的 spot index)
  /// 返回 clone，调用方拥有所有权，无需再 clone
  (ui.Image, int)? getIncremental(int developKey, List<SpotMark> allSpots) {
    if (_rollingResult == null) return null;
    if (developKey != _rollingDevKey) return null;
    if (_rollingSpotCount == 0 || _rollingSpotCount > allSpots.length) {
      return null;
    }
    return (_rollingResult!.clone(), _rollingSpotCount);
  }

  void putSpotsCache(List<SpotMark> spots, ui.Image result) {
    _spotsResult?.dispose();
    _spotsResult = result.clone();
    _spotsKey = computeSpotsKey(spots);
  }

  void putRolling(int developKey, int spotCount, ui.Image result) {
    _rollingResult?.dispose();
    _rollingResult = result.clone();
    _rollingDevKey = developKey;
    _rollingSpotCount = spotCount;
  }

  /// 拖动结束时调用：只失效第一级缓存，保留增量缓存
  /// 增量缓存在 devKey 变化时自动失效
  void invalidateSpotsCache() {
    _spotsResult?.dispose();
    _spotsResult = null;
    _spotsKey = 0;
  }

  /// 换图时调用：全部失效
  void invalidate() {
    _spotsResult?.dispose();
    _spotsResult = null;
    _spotsKey = 0;
    _rollingResult?.dispose();
    _rollingResult = null;
    _rollingDevKey = 0;
    _rollingSpotCount = 0;
  }

  void dispose() => invalidate();
}
