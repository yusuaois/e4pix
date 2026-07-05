import 'dodge_burn_model.dart';

/// Hash all dodge/burn marks into a single integer for cache-key matching.
/// Each mark's hashCode includes its per-mark rendering params (mode/range/exposure).
int hashDodgeBurnMarks(List<DodgeBurnMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
