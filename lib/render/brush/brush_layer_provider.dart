import 'dart:ui' as ui;

import '../../core/models/adjustment_params.dart';
import '../../core/models/brush_layer.dart';

/// 画笔图层提供者接口
///
/// 每个画笔（Spot Removal、Healing、未来画笔）实现此接口
/// 由 [BrushLayerRegistry] 统一管理和调度
abstract class BrushLayerProvider {
  /// 图层唯一标识，如 'spot_removal'、'healing'
  String get id;

  /// 当前参数下该图层是否活跃
  bool isActive(AdjustmentParams params);

  /// 渲染该图层
  ///
  /// [params] 是当前调整参数（包含该画笔的 marks 列表）
  /// [developOutput] 是 Develop + Mask 之后的图像
  /// [developKey] 是 develop 参数的指纹（用于缓存键）
  /// [targetWidth]/[targetHeight] 是输出尺寸
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  });

  /// 预热 GPU 管线状态对象，避免首次笔画卡顿
  /// 默认空操作，各画笔按需覆写
  Future<void> warmup(
    ui.Image developOutput,
    int targetWidth,
    int targetHeight,
  ) async {}

  /// 计算当前 marks 的 hash，用于 committed preview 清除信号
  ///
  /// 渲染完成后 [multi_pass_preview] 遍历活跃 provider 收集所有 hash，
  /// 统一写入 [renderedBrushHashesProvider]，各 overlay 按 [id] 订阅，
  /// hash 匹配时清除本地 committed preview，避免滑块拖动等无关渲染误触发
  int computeMarksHash(AdjustmentParams params) => 0;

  /// 源图变更时使缓存失效
  void invalidate();

  /// 释放 GPU 资源
  void dispose();
}
