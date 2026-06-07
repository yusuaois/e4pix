import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/tethered_shot.dart';
import '../interaction_state.dart';
import '../tether/tether_state.dart';

class CurrentParamsNotifier extends Notifier<AdjustmentParams> {
  @override
  AdjustmentParams build() {
    // 监听 activeShot 切换；切到新 shot 时把 state 拉到那张的 params
    ref.listen<TetheredShot?>(activeShotProvider, (prev, next) {
      if (next != null && next.path != prev?.path) {
        state = next.params;
      }
    });
    return AdjustmentParams.neutral;
  }

  void update(AdjustmentParams newParams) {
    state = newParams;
    final session = ref.read(tetherSessionNotifierProvider);
    final preserve = ref.read(preserveParamsProvider);
    if (session != null && preserve) {
      ref.read(shotsNotifierProvider.notifier).updateAllParams(newParams);
    } else {
      final active = ref.read(activeShotProvider);
      if (active != null) {
        ref
            .read(shotsNotifierProvider.notifier)
            .updateParams(active.path, newParams);
      }
    }
  }

  void reset() => update(AdjustmentParams.neutral);
}

final currentParamsNotifierProvider =
    NotifierProvider<CurrentParamsNotifier, AdjustmentParams>(
      CurrentParamsNotifier.new,
    );

// ── 对比原片 ──

final compareBypassProvider = StateProvider<bool>((ref) => false);

final effectiveParamsProvider = Provider<AdjustmentParams>((ref) {
  if (ref.watch(compareBypassProvider) ||
      ref.watch(compareViewModeProvider) == CompareViewMode.hold) {
    return AdjustmentParams.neutral;
  }
  return ref.watch(currentParamsNotifierProvider);
});

final effectiveLutEnabledProvider = Provider<bool>((ref) {
  return ref.watch(compareViewModeProvider) == CompareViewMode.off;
});
