import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brushes/brush_manifest.dart';
import '../../services/app/app_settings.dart';

/// Compose 图层叠加顺序状态
///
/// [List<String>] 为画笔 ID，从前到后 = 底层→顶层
/// 默认从 [brushManifests] 派生，用户可通过 UI 拖拽重排
/// 持久化到 SharedPreferences
class BrushLayerOrderNotifier extends Notifier<List<String>> {
  bool _loaded = false;

  @override
  List<String> build() {
    if (!_loaded) {
      _loaded = true;
      Future.microtask(() => _initFromSettings());
    }
    return _defaultOrder;
  }

  static List<String> get _defaultOrder =>
      brushManifests.map((m) => m.id).toList();

  void setOrder(List<String> order) {
    if (!_isValid(order)) return;
    state = order;
    AppSettings.setBrushLayerOrder(order);
  }

  Future<void> _initFromSettings() async {
    final saved = await AppSettings.getBrushLayerOrder();
    if (saved != null && _isValid(saved)) {
      state = saved;
    }
  }

  /// 校验 order 的 ID 集合与当前注册的画笔一致
  bool _isValid(List<String> order) {
    final defaultIds = _defaultOrder.toSet();
    return order.length == defaultIds.length &&
        order.toSet().containsAll(defaultIds);
  }
}

final brushLayerOrderProvider =
    NotifierProvider<BrushLayerOrderNotifier, List<String>>(
  BrushLayerOrderNotifier.new,
);
