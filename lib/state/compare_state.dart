import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/models/adjustment_params.dart';
import 'params_state.dart';

/// 是否处于"对比原片"状态。
/// - 按住 CompareButton 或按住 `\` 键 → true
/// - 松开 → false
final compareBypassProvider = StateProvider<bool>((ref) => false);

/// shader / histogram 应使用的参数：
/// bypass 时 neutral，否则当前用户参数
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