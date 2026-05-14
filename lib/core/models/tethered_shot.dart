import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../native/raw_bridge.dart';
import 'adjustment_params.dart';

/// **不可变** —— 改 params / thumbnail 需要 copyWith 返回新实例。
@immutable
class TetheredShot {
  final String path;
  final String filename;
  final DateTime detectedAt;
  final ui.Image? thumbnail;
  final String? error;
  final AdjustmentParams params;

  const TetheredShot({
    required this.path,
    required this.filename,
    required this.detectedAt,
    this.thumbnail,
    this.error,
    this.params = AdjustmentParams.neutral,
  });

  TetheredShot copyWith({
    ui.Image? thumbnail,
    String? error,
    AdjustmentParams? params,
  }) {
    return TetheredShot(
      path: path,
      filename: filename,
      detectedAt: detectedAt,
      thumbnail: thumbnail ?? this.thumbnail,
      error: error ?? this.error,
      params: params ?? this.params,
    );
  }

  static Future<TetheredShot> loadWithThumbnail(TetheredShot shot) async {
    try {
      final raw = await RawBridge.extractThumbnail(shot.path);
      ui.Image? thumb;
      if (raw.isJpegEncoded) {
        final codec = await ui.instantiateImageCodec(raw.pixels as Uint8List);
        final frame = await codec.getNextFrame();
        thumb = frame.image;
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
          rgba, raw.width, raw.height, ui.PixelFormat.rgba8888, c.complete,
        );
        thumb = await c.future;
      }
      return shot.copyWith(thumbnail: thumb);
    } catch (e) {
      return shot.copyWith(error: e.toString());
    }
  }

  void disposeThumbnail() => thumbnail?.dispose();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TetheredShot && other.path == path);

  @override
  int get hashCode => path.hashCode;
}