import 'healing_model.dart';

/// Hash all healing marks into a single integer for cache-key and
/// committed-preview matching.
int hashMarks(List<HealingMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
