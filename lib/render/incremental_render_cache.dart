import 'dart:ui' as ui;

/// Generic two-level render cache for mark-based brush providers.
///
/// Level 1 — Full marks-hash cache (parameter drag optimisation):
///   key = (developKey, hash of all marks)
///   Slider changes → develop output changes, but marks don't → cache hit,
///   0 GPU passes for this brush.
///
/// Level 2 — Incremental rolling cache (new stroke optimisation):
///   key = (developKey, markCount)
///   Same develop params, more marks added → resume from last index.
///   O(N) → O(new marks).
///
/// Cache invalidation conditions:
///   - Drag end: only Level 1 is invalidated (Level 2 survives for next
///     stroke continuation).
///   - Source image change: both levels invalidated.
///
/// ## Ownership convention
///
/// Every [put] stores a clone; every [get] returns a clone. This costs
/// two GPU copies per round-trip (put-clone + get-clone) in exchange for
/// safe multiple cache hits — the same entry can be hit many times across
/// parameter drags without the caller worrying about ownership. The caller
/// that receives a clone from [get] owns it and must dispose it.
///
/// [T] is the mark type. [computeKey] extracts a hashable value from a
/// mark list.
class IncrementalRenderCache<T> {
  // ── Level 1: Marks hash cache ──
  int _marksKey = 0;
  int _marksDevKey = 0;
  ui.Image? _marksResult;

  // ── Level 2: Incremental rolling cache ──
  int _rollingDevKey = 0;
  int _rollingCount = 0;
  ui.Image? _rollingResult;

  final int Function(List<T> marks) computeKey;

  IncrementalRenderCache({required this.computeKey});

  /// Level 1 cache hit: marks list unchanged AND develop params unchanged.
  /// Returns a clone — caller owns it, must dispose.
  ui.Image? getFromMarksCache(int developKey, List<T> marks) {
    if (marks.isEmpty || _marksResult == null) return null;
    if (developKey != _marksDevKey) return null;
    return computeKey(marks) == _marksKey ? _marksResult?.clone() : null;
  }

  /// Level 2 cache hit: returns (intermediate result clone, rendered count).
  /// Returns a clone — caller owns the image in the record, must dispose.
  (ui.Image, int)? getIncremental(int developKey, List<T> marks) {
    if (_rollingResult == null) return null;
    if (developKey != _rollingDevKey) return null;
    if (_rollingCount == 0 || _rollingCount > marks.length) return null;
    return (_rollingResult!.clone(), _rollingCount);
  }

  /// Store a Level 1 cache entry. Clones [result] — caller retains ownership.
  void putMarksCache(int developKey, List<T> marks, ui.Image result) {
    _marksResult?.dispose();
    _marksResult = result.clone();
    _marksKey = computeKey(marks);
    _marksDevKey = developKey;
  }

  /// Store a Level 2 rolling cache entry. Clones [result] — caller retains
  /// ownership.
  void putRolling(int developKey, int count, ui.Image result) {
    _rollingResult?.dispose();
    _rollingResult = result.clone();
    _rollingDevKey = developKey;
    _rollingCount = count;
  }

  /// Invalidate only Level 1 (called on drag end).
  /// Level 2 survives — it auto-invalidates on devKey change.
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
    _rollingCount = 0;
  }

  void dispose() => invalidate();
}
