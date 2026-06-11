import 'dart:ui' as ui;

import '../../core/models/watermark_config.dart';
import '../../utils/image_loader_util.dart';
import '../../render/watermark_geometry.dart';

/// 水印 Logo 加载入口
class WatermarkLogoLoader {
  WatermarkLogoLoader._();

  /// 按配置加载 Logo 图片，无 Logo 时返回 null
  static Future<ui.Image?> load(WatermarkConfig config) async {
    if (config.logoSource == LogoSource.custom &&
        config.customLogoPath != null) {
      return loadWatermarkFileImage(config.customLogoPath!);
    }
    if (config.logoBrand != null) {
      final path = logoAssetPath(config.logoBrand!, config.colorMode);
      return loadAssetImage(path);
    }
    return null;
  }
}
