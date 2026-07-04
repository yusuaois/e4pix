import 'clone_stamp_model.dart';

/// Hash all spots into a single integer for cache-key and
/// committed-preview matching.
int hashSpots(List<SpotMark> spots) =>
    Object.hashAll(spots.map((s) => s.hashCode));
