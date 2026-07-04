import 'spot_heal_model.dart';

/// Hash all spot-heal marks into a single integer for cache-key matching.
int hashMarks(List<SpotHealMark> marks) =>
    Object.hashAll(marks.map((m) => Object.hash(m.target, m.radius, m.hardness)));
