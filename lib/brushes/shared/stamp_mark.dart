import 'dart:ui';

/// 源-目标转移型画笔 mark 的公共接口
///
/// 所有需要 source→target 像素转移的画笔（图章、修复画笔等）
/// 的 mark 都实现此接口，使 [BaseStampOverlayState] 和共享 Painter
/// 工具函数可以泛型操作
abstract class StampMark {
  /// 采样源位置（归一化 [0..1]，源图坐标系）
  Offset get source;

  /// 修复目标位置（归一化 [0..1]，源图坐标系）
  Offset get target;

  /// 笔刷半径（归一化，相对源图宽度）
  double get radius;

  /// 边缘硬度 0..1，1=硬边，0=柔边
  double get hardness;

  /// 序列化为 JSON 兼容的 Map
  Map<String, dynamic> toJson();
}
