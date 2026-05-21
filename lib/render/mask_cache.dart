import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
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
  final int guideEpoch;
  _BrushEntry(this.mask, this.texture, this.guideEpoch);
}

class BrushMaskCache {
  final Map<String, _BrushEntry> _cache = {};

  Future<ui.Image> getOrRasterize(
    String maskId,
    BrushMask mask,
    int w,
    int h, {
    Uint8List? guideBytes,
    int guideWidth = 0,
    int guideHeight = 0,
    int guideEpoch = 0,
    bool allowStaleGuide = false,
  }) async {
    final hasAuto = mask.strokes.any((s) => s.autoMask);
    final e = _cache[maskId];
    final baseOk =
        e != null &&
        identical(e.mask, mask) &&
        e.texture.width == w &&
        e.texture.height == h;
    if (baseOk) {
      if (!hasAuto || e.guideEpoch == guideEpoch || allowStaleGuide) {
        return e.texture;
      }
    }

    final tex = await rasterizeBrushMask(
      mask,
      w,
      h,
      guideBytes: guideBytes,
      guideWidth: guideWidth,
      guideHeight: guideHeight,
    );
    e?.texture.dispose();
    _cache[maskId] = _BrushEntry(mask, tex, guideEpoch);
    return tex;
  }

  void dispose() {
    for (final e in _cache.values) {
      e.texture.dispose();
    }
    _cache.clear();
  }
}

Future<ui.Image> rasterizeBrushMask(
  BrushMask mask,
  int w,
  int h, {
  Uint8List? guideBytes,
  int guideWidth = 0,
  int guideHeight = 0,
}) async {
  final hasAuto = mask.strokes.any((s) => s.autoMask);
  final guideOk = guideBytes != null && guideWidth == w && guideHeight == h;
  if (!hasAuto || !guideOk) {
    return _rasterizeGeometric(mask, w, h);
  }
  return _rasterizeAuto(mask, w, h, guideBytes);
}

Future<ui.Image> _rasterizeGeometric(BrushMask mask, int w, int h) async {
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

Future<ui.Image> _rasterizeAuto(
  BrushMask mask,
  int w,
  int h,
  Uint8List guide,
) async {
  final acc = Float32List(w * h);
  int ux0 = w, uy0 = h, ux1 = -1, uy1 = -1;

  for (final stroke in mask.strokes) {
    final flow = stroke.flow.clamp(0.0, 1.0);
    if (flow <= 0 || stroke.points.isEmpty) continue;

    final radiusPx = stroke.radius * w;
    if (radiusPx < 0.5) continue;
    final inner = radiusPx * stroke.hardness.clamp(0.0, 1.0);
    final hardEdge = (radiusPx - inner) < 1.0;

    final pts = _decimate(stroke.points, w, h, radiusPx * 0.4);

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      final px = p.dx * w, py = p.dy * h;
      if (px < minX) minX = px;
      if (py < minY) minY = py;
      if (px > maxX) maxX = px;
      if (py > maxY) maxY = py;
    }
    final x0 = (minX - radiusPx).floor().clamp(0, w - 1);
    final y0 = (minY - radiusPx).floor().clamp(0, h - 1);
    final x1 = (maxX + radiusPx).ceil().clamp(0, w - 1);
    final y1 = (maxY + radiusPx).ceil().clamp(0, h - 1);
    if (x1 < x0 || y1 < y0) continue;

    if (x0 < ux0) ux0 = x0;
    if (y0 < uy0) uy0 = y0;
    if (x1 > ux1) ux1 = x1;
    if (y1 > uy1) uy1 = y1;

    final bw = x1 - x0 + 1;
    final geomMax = Float32List(bw * (y1 - y0 + 1));

    final segCount = pts.length == 1 ? 1 : pts.length - 1;
    for (int s = 0; s < segCount; s++) {
      final ax = pts[s].dx * w, ay = pts[s].dy * h;
      final bx = (pts.length == 1 ? pts[0].dx : pts[s + 1].dx) * w;
      final by = (pts.length == 1 ? pts[0].dy : pts[s + 1].dy) * h;
      final sx0 = ((ax < bx ? ax : bx) - radiusPx).floor().clamp(x0, x1);
      final sy0 = ((ay < by ? ay : by) - radiusPx).floor().clamp(y0, y1);
      final sx1 = ((ax > bx ? ax : bx) + radiusPx).ceil().clamp(x0, x1);
      final sy1 = ((ay > by ? ay : by) + radiusPx).ceil().clamp(y0, y1);
      for (int y = sy0; y <= sy1; y++) {
        for (int x = sx0; x <= sx1; x++) {
          final d = _distToSeg(x + 0.5, y + 0.5, ax, ay, bx, by);
          if (d >= radiusPx) continue;
          final g = hardEdge
              ? 1.0
              : (d <= inner
                    ? 1.0
                    : _smoothDown((d - inner) / (radiusPx - inner)));
          final li = (y - y0) * bw + (x - x0);
          if (g > geomMax[li]) geomMax[li] = g;
        }
      }
    }

    double refR = 0, refG = 0, refB = 0;
    if (stroke.autoMask) {
      int n = 0;
      for (final p in pts) {
        final gx = (p.dx * w).round().clamp(0, w - 1);
        final gy = (p.dy * h).round().clamp(0, h - 1);
        final gi = (gy * w + gx) * 4;
        refR += guide[gi];
        refG += guide[gi + 1];
        refB += guide[gi + 2];
        n++;
      }
      if (n > 0) {
        refR /= n;
        refG /= n;
        refB /= n;
      }
    }
    final tol = stroke.tolerance.clamp(0.01, 1.0);

    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        final li = (y - y0) * bw + (x - x0);
        final gm = geomMax[li];
        if (gm <= 0) continue;
        double wgt = gm;
        if (stroke.autoMask) {
          final gi = (y * w + x) * 4;
          final dr = (guide[gi] - refR) / 255.0;
          final dg = (guide[gi + 1] - refG) / 255.0;
          final db = (guide[gi + 2] - refB) / 255.0;
          final dist = math.sqrt(dr * dr + dg * dg + db * db) / 1.7320508;
          wgt *= _colorFalloff(dist, tol);
        }
        wgt *= flow;
        if (wgt <= 0) continue;
        final ai = y * w + x;
        if (stroke.erase) {
          acc[ai] = acc[ai] * (1.0 - wgt);
        } else {
          acc[ai] = acc[ai] + (1.0 - acc[ai]) * wgt;
        }
      }
    }
  }

  if (ux1 >= ux0 && uy1 >= uy0) {
    final r = (w * 0.006).round().clamp(2, 32);
    const eps = 0.0025;
    final bx0 = (ux0 - r) < 0 ? 0 : (ux0 - r);
    final by0 = (uy0 - r) < 0 ? 0 : (uy0 - r);
    final bx1 = (ux1 + r) > w - 1 ? w - 1 : (ux1 + r);
    final by1 = (uy1 + r) > h - 1 ? h - 1 : (uy1 + r);
    _fastGuidedRefine(acc, guide, w, bx0, by0, bx1, by1, r, eps);
  }

  final rgba = Uint8List(w * h * 4);
  for (int i = 0; i < w * h; i++) {
    int v = (acc[i] * 255.0).round();
    if (v < 0) v = 0;
    if (v > 255) v = 255;
    final o = i * 4;
    rgba[o] = v;
    rgba[o + 1] = v;
    rgba[o + 2] = v;
    rgba[o + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void _fastGuidedRefine(
  Float32List acc,
  Uint8List guide,
  int w,
  int bx0,
  int by0,
  int bx1,
  int by1,
  int r,
  double eps,
) {
  final bw = bx1 - bx0 + 1;
  final bh = by1 - by0 + 1;
  final area = bw * bh;

  int s = 1;
  if (area > 1200000) {
    s = math.sqrt(area / 1200000).ceil();
    if (s > 8) s = 8;
  }

  final iFull = Float32List(area);
  for (int j = 0; j < bh; j++) {
    final gy = by0 + j;
    final rowBase = j * bw;
    for (int i = 0; i < bw; i++) {
      final gi = (gy * w + (bx0 + i)) * 4;
      iFull[rowBase + i] =
          (0.299 * guide[gi] + 0.587 * guide[gi + 1] + 0.114 * guide[gi + 2]) /
          255.0;
    }
  }

  final dbw = (bw + s - 1) ~/ s;
  final dbh = (bh + s - 1) ~/ s;
  final dn = dbw * dbh;
  final id = Float32List(dn);
  final pd = Float32List(dn);
  for (int dj = 0; dj < dbh; dj++) {
    final sj = math.min(dj * s, bh - 1);
    final gy = by0 + sj;
    for (int di = 0; di < dbw; di++) {
      final si = math.min(di * s, bw - 1);
      id[dj * dbw + di] = iFull[sj * bw + si];
      pd[dj * dbw + di] = acc[gy * w + (bx0 + si)];
    }
  }

  final rd = (r ~/ s) < 1 ? 1 : (r ~/ s);
  final meanI = _boxMean(id, dbw, dbh, rd);
  final meanP = _boxMean(pd, dbw, dbh, rd);
  final ii = Float32List(dn);
  final ip = Float32List(dn);
  for (int k = 0; k < dn; k++) {
    ii[k] = id[k] * id[k];
    ip[k] = id[k] * pd[k];
  }
  final meanII = _boxMean(ii, dbw, dbh, rd);
  final meanIp = _boxMean(ip, dbw, dbh, rd);

  final a = Float32List(dn);
  final b = Float32List(dn);
  for (int k = 0; k < dn; k++) {
    final varI = meanII[k] - meanI[k] * meanI[k];
    final covIp = meanIp[k] - meanI[k] * meanP[k];
    final ak = covIp / (varI + eps);
    a[k] = ak;
    b[k] = meanP[k] - ak * meanI[k];
  }
  final meanA = _boxMean(a, dbw, dbh, rd);
  final meanB = _boxMean(b, dbw, dbh, rd);

  for (int j = 0; j < bh; j++) {
    final fy = j / s;
    int ly0 = fy.floor();
    final wy = fy - ly0;
    int ly1 = ly0 + 1;
    if (ly0 > dbh - 1) ly0 = dbh - 1;
    if (ly1 > dbh - 1) ly1 = dbh - 1;
    final gy = by0 + j;
    final rowBase = j * bw;
    for (int i = 0; i < bw; i++) {
      final fx = i / s;
      int lx0 = fx.floor();
      final wx = fx - lx0;
      int lx1 = lx0 + 1;
      if (lx0 > dbw - 1) lx0 = dbw - 1;
      if (lx1 > dbw - 1) lx1 = dbw - 1;
      final aa = _bilerp(meanA, dbw, lx0, lx1, ly0, ly1, wx, wy);
      final bb = _bilerp(meanB, dbw, lx0, lx1, ly0, ly1, wx, wy);
      double q = aa * iFull[rowBase + i] + bb;
      if (q < 0) q = 0;
      if (q > 1) q = 1;
      acc[gy * w + (bx0 + i)] = q;
    }
  }
}

double _bilerp(
  Float32List m,
  int dbw,
  int x0,
  int x1,
  int y0,
  int y1,
  double wx,
  double wy,
) {
  final v00 = m[y0 * dbw + x0];
  final v01 = m[y0 * dbw + x1];
  final v10 = m[y1 * dbw + x0];
  final v11 = m[y1 * dbw + x1];
  final top = v00 + (v01 - v00) * wx;
  final bot = v10 + (v11 - v10) * wx;
  return top + (bot - top) * wy;
}

Float32List _boxMean(Float32List src, int bw, int bh, int r) {
  final stride = bw + 1;
  final sat = Float64List(stride * (bh + 1));
  for (int j = 0; j < bh; j++) {
    double rowsum = 0;
    final rb = j * bw;
    final sr = (j + 1) * stride;
    final sp = j * stride;
    for (int i = 0; i < bw; i++) {
      rowsum += src[rb + i];
      sat[sr + i + 1] = sat[sp + i + 1] + rowsum;
    }
  }
  final out = Float32List(bw * bh);
  for (int j = 0; j < bh; j++) {
    final y1 = j - r < 0 ? 0 : j - r;
    final y2 = j + r >= bh ? bh - 1 : j + r;
    for (int i = 0; i < bw; i++) {
      final x1 = i - r < 0 ? 0 : i - r;
      final x2 = i + r >= bw ? bw - 1 : i + r;
      final ssum =
          sat[(y2 + 1) * stride + (x2 + 1)] -
          sat[y1 * stride + (x2 + 1)] -
          sat[(y2 + 1) * stride + x1] +
          sat[y1 * stride + x1];
      out[j * bw + i] = ssum / ((y2 - y1 + 1) * (x2 - x1 + 1));
    }
  }
  return out;
}

List<ui.Offset> _decimate(
  List<ui.Offset> pts,
  int w,
  int h,
  double minSpacingPx,
) {
  if (pts.length <= 2 || minSpacingPx <= 0.5) return pts;
  final out = <ui.Offset>[pts.first];
  double lastX = pts.first.dx * w, lastY = pts.first.dy * h;
  for (int i = 1; i < pts.length - 1; i++) {
    final px = pts[i].dx * w, py = pts[i].dy * h;
    final dx = px - lastX, dy = py - lastY;
    if (dx * dx + dy * dy >= minSpacingPx * minSpacingPx) {
      out.add(pts[i]);
      lastX = px;
      lastY = py;
    }
  }
  out.add(pts.last);
  return out;
}

double _distToSeg(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-6) {
    final ex = px - ax, ey = py - ay;
    return math.sqrt(ex * ex + ey * ey);
  }
  double t = ((px - ax) * dx + (py - ay) * dy) / len2;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final cx = ax + t * dx, cy = ay + t * dy;
  final ex = px - cx, ey = py - cy;
  return math.sqrt(ex * ex + ey * ey);
}

double _smoothDown(double t) {
  if (t <= 0) return 1.0;
  if (t >= 1) return 0.0;
  return 1.0 - t * t * (3 - 2 * t);
}

double _colorFalloff(double dist, double tol) {
  final t = dist / (tol <= 1e-4 ? 1e-4 : tol);
  if (t <= 0) return 1.0;
  if (t >= 1) return 0.0;
  return 1.0 - t * t * (3 - 2 * t);
}
