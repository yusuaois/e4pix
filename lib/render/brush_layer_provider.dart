import 'dart:ui' as ui;

import '../core/models/adjustment_params.dart';
import '../core/models/brush_layer.dart';

/// 画笔图层提供者接口。
///
/// 每个画笔（Spot Removal、Healing、未来画笔）实现此接口，
/// 由 [BrushLayerRegistry] 统一管理和调度。
abstract class BrushLayerProvider {
  /// 图层唯一标识，如 'spot_removal'、'healing'。
  String get id;

  /// 当前参数下该图层是否活跃。
  bool isActive(AdjustmentParams params);

  /// 渲染该图层。
  ///
  /// [params] 是当前调整参数（包含该画笔的 marks 列表），
  /// [developOutput] 是 Develop + Mask 之后的图像，
  /// [developKey] 是 develop 参数的指纹（用于缓存键），
  /// [targetWidth]/[targetHeight] 是输出尺寸。
  Future<BrushLayer> render({
    required AdjustmentParams params,
    required ui.Image developOutput,
    required int developKey,
    required int targetWidth,
    required int targetHeight,
  });

  /// 源图变更时使缓存失效。
  void invalidate();

  /// 释放 GPU 资源。
  void dispose();
}
