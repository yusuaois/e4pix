import '../core/models/adjustment_params.dart';
import 'brush_layer_provider.dart';

/// 画笔图层有序注册表。
///
/// 图层的注册顺序决定 Compose pass 中的混合顺序（先注册在下层，后注册在上层）。
/// 添加新画笔时只需在此注册一个 [BrushLayerProvider] 即可接入全管线。
class BrushLayerRegistry {
  final List<BrushLayerProvider> providers;

  const BrushLayerRegistry({required this.providers});

  /// 返回当前参数下所有活跃的图层提供者（保持注册顺序）。
  List<BrushLayerProvider> activeProviders(AdjustmentParams params) =>
      providers.where((p) => p.isActive(params)).toList();

  /// 是否有任一图层活跃。
  bool hasActive(AdjustmentParams params) =>
      providers.any((p) => p.isActive(params));

  /// 源图变更时使全部图层缓存失效。
  void invalidateAll() {
    for (final p in providers) {
      p.invalidate();
    }
  }

  /// 释放全部图层的 GPU 资源。
  void dispose() {
    for (final p in providers) {
      p.dispose();
    }
  }
}
