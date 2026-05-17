import 'dart:ui' as ui;
import 'dart:ui';

import '../models/crop_params.dart';

Future<ui.Image> cropImage(ui.Image src, CropParams crop) async {
  final pr = ui.PictureRecorder();
  final canvas = Canvas(pr);
  final w = src.width.toDouble();
  final h = src.height.toDouble();
  final srcRect = Rect.fromLTWH(crop.x * w, crop.y * h, crop.width * w, crop.height * h);
  final dstRect = Rect.fromLTWH(0, 0, srcRect.width, srcRect.height);
  canvas.drawImageRect(src, srcRect, dstRect, Paint());
  return pr.endRecording().toImage(srcRect.width.round(), srcRect.height.round());
}