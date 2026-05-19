import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../core/models/tethered_shot.dart';
import 'tether_state.dart';

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
    if (session == null) return;

    final preserve = ref.read(preserveParamsProvider);
    if (preserve) {
      ref.read(shotsNotifierProvider.notifier).updateAllParams(newParams);
    } else {
      final active = ref.read(activeShotProvider);
      if (active != null) {
        ref.read(shotsNotifierProvider.notifier).updateParams(active.path, newParams);
      }
    }
  }

  void reset() => update(AdjustmentParams.neutral);
}

final currentParamsNotifierProvider =
    NotifierProvider<CurrentParamsNotifier, AdjustmentParams>(
  CurrentParamsNotifier.new,
);