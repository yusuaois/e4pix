import 'dart:ui' as ui;

import 'spot_heal_model.dart';

/// Two-level cache for Spot Heal marks, mirroring [SpotRemovalCache].
///
/// Level 1: full marks-hash cache — re-hit when params change but marks unchanged.
/// Level 2: incremental rolling cache — only re-renders newly added marks.
class SpotHealCache {
  // Level 1: (developKey, marksHash) → Image
  final Map<(int, int), ui.Image> _marksCache = {};
  // Level 2: (developKey, markCount) → (Image, count)
  ui.Image? _rollingImage;
  int _rollingCount = 0;
  int _rollingKey = 0;

  static int computeKey(List<SpotHealMark> marks) =>
      Object.hashAll(marks.map((m) => Object.hash(m.target, m.radius, m.hardness)));

  /// Level 1 lookup: full marks hash match.
  ui.Image? getFromMarksCache(int developKey, List<SpotHealMark> marks) {
    final key = (developKey, computeKey(marks));
    final img = _marksCache[key];
    return img?.clone();
  }

  /// Level 2 lookup: incremental — returns (image, startIndex) if rolling cache hit.
  (ui.Image, int)? getIncremental(int developKey, List<SpotHealMark> marks) {
    final count = marks.length;
    if (_rollingImage == null || _rollingKey != developKey || count <= _rollingCount) {
      return null;
    }
    return (_rollingImage!.clone(), _rollingCount);
  }

  /// Store Level 1 result.
  void putMarksCache(int developKey, List<SpotHealMark> marks, ui.Image image) {
    final key = (developKey, computeKey(marks));
    _marksCache[key] = image.clone();
  }

  /// Store Level 2 rolling result.
  void putRolling(int developKey, int count, ui.Image image) {
    _rollingImage?.dispose();
    _rollingImage = image.clone();
    _rollingCount = count;
    _rollingKey = developKey;
  }

  void invalidate() {
    for (final img in _marksCache.values) {
      img.dispose();
    }
    _marksCache.clear();
    _rollingImage?.dispose();
    _rollingImage = null;
    _rollingCount = 0;
  }

  void dispose() => invalidate();
}
