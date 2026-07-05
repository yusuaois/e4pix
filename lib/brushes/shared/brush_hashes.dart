import '../clone_stamp/clone_stamp_model.dart';
import '../healing/healing_model.dart';
import '../spot_heal/spot_heal_model.dart';
import '../dodge_burn/dodge_burn_model.dart';

/// Hash all clone-stamp spots into a single integer for cache-key and
/// committed-preview matching.
int hashSpots(List<SpotMark> spots) =>
    Object.hashAll(spots.map((s) => s.hashCode));

/// Hash all healing marks into a single integer for cache-key and
/// committed-preview matching.
int hashHealingMarks(List<HealingMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));

/// Hash all spot-heal marks into a single integer for cache-key matching.
int hashSpotHealMarks(List<SpotHealMark> marks) => Object.hashAll(
  marks.map((m) => Object.hash(m.target, m.radius, m.hardness)),
);

/// Hash all dodge/burn marks into a single integer for cache-key matching.
/// Each mark's hashCode includes its per-mark rendering params (mode/range/exposure).
int hashDodgeBurnMarks(List<DodgeBurnMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
