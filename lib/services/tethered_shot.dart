import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/models/adjustment_params.dart';
import '../native/raw_bridge.dart';

/// 元数据 + 缩略图。
class TetheredShot {
  final String path;
  final String filename;
  final DateTime detectedAt;
  ui.Image? thumbnail;
  String? error;

  AdjustmentParams params;

  TetheredShot({
    required this.path,
    required this.filename,
    required this.detectedAt,
    this.params = AdjustmentParams.neutral,
  });

  /// 提取相机内嵌缩略图
  Future<void> loadThumbnail() async {
    try {
      final raw = await RawBridge.extractThumbnail(path);
      if (raw.isJpegEncoded) {
        final codec = await ui.instantiateImageCodec(raw.pixels as Uint8List);
        final frame = await codec.getNextFrame();
        thumbnail = frame.image;
      } else if (raw.pixels is Uint8List) {
        final px = raw.pixels as Uint8List;
        final rgba = Uint8List(raw.width * raw.height * 4);
        for (int i = 0, j = 0; i < px.length; i += 3, j += 4) {
          rgba[j] = px[i];
          rgba[j + 1] = px[i + 1];
          rgba[j + 2] = px[i + 2];
          rgba[j + 3] = 255;
        }
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          rgba, raw.width, raw.height, ui.PixelFormat.rgba8888, c.complete);
        thumbnail = await c.future;
      }
    } catch (e) {
      error = e.toString();
    }
  }

  void dispose() => thumbnail?.dispose();
}