import 'dart:ui' as ui;

import 'healing_model.dart';

/// Healing brush result cache (two-level).
///
/// Level 1 — Marks hash cache (parameter drag optimisation):
///   key = Object.hashAll(marks.hashCode)
///   Slider changes → develop output changes, but marks don't → cache hit,
///   0 GPU passes for healing.
///
/// Level 2 — Incremental rolling cache (new stroke optimisation):
///   key = (developKey, markCount)
///   Same develop params, more marks added → resume from last index.
///   O(N) → O(new marks).
///
/// ## Ownership convention
///
/// See [SpotRemovalCache] — same store-clone / get-clone pattern for
/// safe multiple cache hits.
class HealingCache {
  // ── Level 1: Marks hash cache ──
  int _marksKey = 0;
  int _marksDevKey = 0;
  ui.Image? _marksResult;

  // ── Level 2: Incremental rolling cache ──
  int _rollingDevKey = 0;
  int _rollingMarkCount = 0;
  ui.Image? _rollingResult;

  static int computeHealingKey(List<HealingMark> marks) =>
      Object.hashAll(marks.map((m) => m.hashCode));

  /// Level 1 cache hit: marks list unchanged AND develop params unchanged.
  /// Returns a clone — caller owns it.
  ui.Image? getFromMarksCache(int developKey, List<HealingMark> marks) {
    if (marks.isEmpty || _marksResult == null) return null;
    if (developKey != _marksDevKey) return null;
    return computeHealingKey(marks) == _marksKey
        ? _marksResult?.clone()
        : null;
  }

  /// Level 2 cache hit: returns (intermediate result clone, rendered count).
  /// Returns a clone — caller owns it.
  (ui.Image, int)? getIncremental(int developKey, List<HealingMark> allMarks) {
    if (_rollingResult == null) return null;
    if (developKey != _rollingDevKey) return null;
    if (_rollingMarkCount == 0 || _rollingMarkCount > allMarks.length) {
      return null;
    }
    return (_rollingResult!.clone(), _rollingMarkCount);
  }

  void putMarksCache(int developKey, List<HealingMark> marks, ui.Image result) {
    _marksResult?.dispose();
    _marksResult = result.clone();
    _marksKey = computeHealingKey(marks);
    _marksDevKey = developKey;
  }

  void putRolling(int developKey, int markCount, ui.Image result) {
    _rollingResult?.dispose();
    _rollingResult = result.clone();
    _rollingDevKey = developKey;
    _rollingMarkCount = markCount;
  }

  /// Invalidate only the marks-hash cache (called on drag end).
  /// Incremental cache survives — it auto-invalidates on devKey change.
  void invalidateMarksCache() {
    _marksResult?.dispose();
    _marksResult = null;
    _marksKey = 0;
  }

  /// Full invalidation (source image changed).
  void invalidate() {
    _marksResult?.dispose();
    _marksResult = null;
    _marksKey = 0;
    _rollingResult?.dispose();
    _rollingResult = null;
    _rollingDevKey = 0;
    _rollingMarkCount = 0;
  }

  void dispose() => invalidate();
}
