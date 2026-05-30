// lib/state/filter_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/tethered_shot.dart';
import 'providers.dart';

enum FlagFilter { all, pickOnly, rejectHidden }

@immutable
class ShotFilter {
  final int minRating;     // 0 = 不限
  final FlagFilter flag;   // all = 不限

  const ShotFilter({this.minRating = 0, this.flag = FlagFilter.all});

  bool get isActive => minRating > 0 || flag != FlagFilter.all;

  bool matches(TetheredShot s) {
    if (s.rating < minRating) return false;
    switch (flag) {
      case FlagFilter.pickOnly:
        if (s.flag != ShotFlag.pick) return false;
      case FlagFilter.rejectHidden:
        if (s.flag == ShotFlag.reject) return false;
      case FlagFilter.all:
        break;
    }
    return true;
  }

  ShotFilter copyWith({int? minRating, FlagFilter? flag}) =>
      ShotFilter(minRating: minRating ?? this.minRating, flag: flag ?? this.flag);
}

class ShotFilterNotifier extends Notifier<ShotFilter> {
  @override
  ShotFilter build() => const ShotFilter();
  void setMinRating(int r) => state = state.copyWith(minRating: r);
  void setFlag(FlagFilter f) => state = state.copyWith(flag: f);
  void reset() => state = const ShotFilter();
}

final shotFilterProvider =
    NotifierProvider<ShotFilterNotifier, ShotFilter>(ShotFilterNotifier.new);

/// 过滤后的 shots
final filteredShotsProvider = Provider<List<TetheredShot>>((ref) {
  final shots = ref.watch(shotsNotifierProvider);
  final filter = ref.watch(shotFilterProvider);
  if (!filter.isActive) return shots;
  return shots.where(filter.matches).toList();
});