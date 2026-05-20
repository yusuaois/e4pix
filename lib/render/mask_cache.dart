import 'dart:ui' as ui;

import '../core/models/mask_shape.dart';

class DevelopPassCache {
  ui.Image? _image;
  Object? _key;

  Future<ui.Image> getOrCompute(
    Object key,
    Future<ui.Image> Function() compute,
  ) async {
    if (_key == key && _image != null) return _image!;
    final img = await compute();
    if (!identical(_image, img)) _image?.dispose();
    _image = img;
    _key = key;
    return img;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _key = null;
  }
}

class _BrushEntry {
  final BrushMask mask;
  final ui.Image texture;
  _BrushEntry(this.mask, this.texture);
}

class BrushMaskCache {
  final Map<String, _BrushEntry> _cache = {};

  Future<ui.Image> getOrRasterize(
    String maskId,
    BrushMask mask,
    int w,
    int h,
  ) async {
    final e = _cache[maskId];
    if (e != null &&
        identical(e.mask, mask) &&
        e.texture.width == w &&
        e.texture.height == h) {
      return e.texture;
    }
    final tex = await rasterizeBrushMask(mask, w, h);
    e?.texture.dispose();
    _cache[maskId] = _BrushEntry(mask, tex);
    return tex;
  }

  void dispose() {
    for (final e in _cache.values) {
      e.texture.dispose();
    }
    _cache.clear();
  }
}

Future<ui.Image> rasterizeBrushMask(BrushMask mask, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final bounds = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

  canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xFF000000));

  for (final stroke in mask.strokes) {
    final isErase = stroke.erase;
    final flow = stroke.flow.clamp(0.0, 1.0);
    if (flow <= 0) continue;

    final strokeWidthPx = stroke.radius * 2 * w;
    final sigma = strokeWidthPx * (1.0 - stroke.hardness) * 0.25;

    final inkColor = isErase
        ? const ui.Color(0xFF000000)
        : const ui.Color(0xFFFFFFFF);
    final layerPaint = ui.Paint()
      ..color = isErase
          ? ui.Color.fromRGBO(0, 0, 0, flow)
          : ui.Color.fromRGBO(255, 255, 255, flow);

    canvas.saveLayer(bounds, layerPaint);

    final paint = ui.Paint()
      ..color = inkColor
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeWidth = strokeWidthPx;
    if (sigma > 0.5) {
      paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
    }

    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      final dot = ui.Paint()
        ..color = inkColor
        ..style = ui.PaintingStyle.fill;
      if (sigma > 0.5) {
        dot.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
      }
      canvas.drawCircle(ui.Offset(p.dx * w, p.dy * h), stroke.radius * w, dot);
    } else {
      final path = ui.Path();
      final p0 = stroke.points.first;
      path.moveTo(p0.dx * w, p0.dy * h);
      for (int k = 1; k < stroke.points.length; k++) {
        final p = stroke.points[k];
        path.lineTo(p.dx * w, p.dy * h);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}
