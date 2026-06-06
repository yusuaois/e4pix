import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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

/// 是否处于"对比原片"状态。按住 CompareButton 或 `\` 键 → true，松开 → false。
final compareBypassProvider = StateProvider<bool>((ref) => false);

/// shader / histogram 应使用的参数：bypass 时 neutral，否则当前用户参数
final effectiveParamsProvider = Provider<AdjustmentParams>((ref) {
  if (ref.watch(compareBypassProvider)) {
    return AdjustmentParams.neutral;
  }
  return ref.watch(currentParamsNotifierProvider);
});

/// LUT 是否应当生效（bypass 时禁用）
final effectiveLutEnabledProvider = Provider<bool>((ref) {
  return !ref.watch(compareBypassProvider);
});
