import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/models/tethered_shot.dart';
import '../../services/export/sidecar_service.dart';

class SidecarWriter {
  final Map<String, Timer> _timers = {};
  static const _debounce = Duration(milliseconds: 500);

  /// debounce 写（参数变化用）
  void schedule(String rawPath, AdjustmentParams params, int rating, ShotFlag flag) {
    _timers[rawPath]?.cancel();
    _timers[rawPath] = Timer(_debounce, () {
      _timers.remove(rawPath);
      SidecarService.write(rawPath, params: params, rating: rating, flag: flag);
    });
  }

  /// 立即写（星标/旗标即时）
  void writeNow(String rawPath, AdjustmentParams params, int rating, ShotFlag flag) {
    _timers[rawPath]?.cancel();
    _timers.remove(rawPath);
    SidecarService.write(rawPath, params: params, rating: rating, flag: flag);
  }

  void dispose() {
    for (final t in _timers.values) { t.cancel(); }
    _timers.clear();
  }
}

final sidecarWriterProvider = Provider<SidecarWriter>((ref) {
  final w = SidecarWriter();
  ref.onDispose(w.dispose);
  return w;
});