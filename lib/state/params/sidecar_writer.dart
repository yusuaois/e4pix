import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/models/tethered_shot.dart';
import '../../utils/debouncer.dart';
import '../../services/export/sidecar_service.dart';

class SidecarWriter {
  final _debouncer = KeyedDebouncer<String>(const Duration(milliseconds: 500));

  /// debounce 写（参数变化用）
  void schedule(
    String rawPath,
    AdjustmentParams params,
    int rating,
    ShotFlag flag,
  ) {
    _debouncer.schedule(rawPath, () {
      SidecarService.write(rawPath, params: params, rating: rating, flag: flag);
    });
  }

  /// 立即写（星标/旗标即时）
  void writeNow(
    String rawPath,
    AdjustmentParams params,
    int rating,
    ShotFlag flag,
  ) {
    _debouncer.runNow(rawPath, () {
      SidecarService.write(rawPath, params: params, rating: rating, flag: flag);
    });
  }

  void dispose() => _debouncer.dispose();
}

final sidecarWriterProvider = Provider<SidecarWriter>((ref) {
  final w = SidecarWriter();
  ref.onDispose(w.dispose);
  return w;
});
