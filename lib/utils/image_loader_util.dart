import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../services/watermark/watermark_asset_manager.dart';

/// 共享图片解码工具：bytes → ui.Image
///
/// instantiateImageCodec → getNextFrame
Future<ui.Image?> decodeImageFromBytes(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (e) {
    debugPrint('[ImageUtil] decodeImageFromBytes failed: $e');
    return null;
  }
}

/// 从 Asset 路径加载图片
Future<ui.Image?> loadAssetImage(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return decodeImageFromBytes(data.buffer.asUint8List());
  } catch (e) {
    debugPrint('[ImageUtil] loadAssetImage "$assetPath" failed: $e');
    return null;
  }
}

/// 从水印资产目录加载文件图片
Future<ui.Image?> loadWatermarkFileImage(String filePath) async {
  try {
    final bytes = await WatermarkAssetManager.readImageBytes(filePath);
    if (bytes == null) return null;
    return decodeImageFromBytes(bytes);
  } catch (e) {
    debugPrint('[ImageUtil] loadWatermarkFileImage "$filePath" failed: $e');
    return null;
  }
}
