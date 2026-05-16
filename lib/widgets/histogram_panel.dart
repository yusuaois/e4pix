import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models/adjustment_params.dart';
import '../render/render_engine.dart';

class Histogram {
  final Int32List red, green, blue, luma;
  final int totalPixels;

  const Histogram._(
    this.red,
    this.green,
    this.blue,
    this.luma,
    this.totalPixels,
  );

  factory Histogram.fromRgba(Uint8List px) {
    final r = Int32List(256), g = Int32List(256);
    final b = Int32List(256), l = Int32List(256);
    final n = px.length ~/ 4;
    for (int i = 0; i < px.length; i += 4) {
      final ri = px[i], gi = px[i + 1], bi = px[i + 2];
      r[ri]++;
      g[gi]++;
      b[bi]++;
      // Rec.709
      l[((ri * 54 + gi * 183 + bi * 19) >> 8).clamp(0, 255)]++;
    }
    return Histogram._(r, g, b, l, n);
  }

  static final empty = Histogram._(_zero, _zero, _zero, _zero, 0);
  static final _zero = Int32List(256);
}

// Histogram
class LiveHistogramPanel extends StatefulWidget {
  final ui.FragmentProgram program;
  final ui.Image? sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;

  const LiveHistogramPanel({
    super.key,
    required this.program,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
  });

  @override
  State<LiveHistogramPanel> createState() => _LiveHistogramPanelState();
}

class _LiveHistogramPanelState extends State<LiveHistogramPanel> {
  Histogram _hist = Histogram.empty;
  Timer? _debounce;
  bool _computing = false;
  static const _thumbDim = 256;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(LiveHistogramPanel old) {
    super.didUpdateWidget(old);
    if (old.params != widget.params ||
        old.sourceImage != widget.sourceImage ||
        old.lutTexture != widget.lutTexture) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 33), _recompute);
  }

  Future<void> _recompute() async {
    if (_computing || widget.sourceImage == null) return;
    _computing = true;
    final captured = widget.sourceImage!;
    try {
      final src = captured;
      // 等比缩到 256 长边
      final scale =
          _thumbDim / (src.width > src.height ? src.width : src.height);
      final w = (src.width * scale).round().clamp(16, _thumbDim);
      final h = (src.height * scale).round().clamp(16, _thumbDim);

      if (!mounted || widget.sourceImage != captured) return;

      final rendered = await RenderEngine.renderToImage(
        program: widget.program,
        sourceImage: src,
        params: widget.params,
        lutTexture: widget.lutTexture,
        lutSize: widget.lutSize,
        targetWidth: w,
        targetHeight: h,
      );
      try {
        if (!mounted || widget.sourceImage != captured) return;
        final bd = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (bd == null) return;
        if (!mounted || widget.sourceImage != captured) return;
        final hist = Histogram.fromRgba(bd.buffer.asUint8List());
        if (mounted) setState(() => _hist = hist);
      } finally {
        rendered.dispose();
      }
    } catch (e) {
      debugPrint('Histogram recompute error: $e');
    } finally {
      _computing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: CustomPaint(painter: _HistogramPainter(_hist)),
    );
  }
}

// Histogram Painter
class _HistogramPainter extends CustomPainter {
  final Histogram h;
  _HistogramPainter(this.h);

  @override
  void paint(Canvas canvas, Size size) {
    if (h.totalPixels == 0) return;

    int peak = 1;
    for (int i = 1; i < 255; i++) {
      if (h.luma[i] > peak) peak = h.luma[i];
    }
    final norm = (peak * 1.15).toDouble();

    canvas.drawPath(
      _fillPath(h.luma, size, norm),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );

    void line(Int32List data, Color color) {
      canvas.drawPath(
        _strokePath(data, size, norm),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..isAntiAlias = true,
      );
    }

    line(h.red, const Color(0xFFFF6464).withValues(alpha: 0.9));
    line(h.green, const Color(0xFF60E060).withValues(alpha: 0.9));
    line(h.blue, const Color(0xFF6088FF).withValues(alpha: 0.9));

    // 削波警示
    final clip = Paint()..color = Colors.redAccent.withValues(alpha: 0.65);
    final th = h.totalPixels * 0.01;
    if (h.red[0] > th || h.green[0] > th || h.blue[0] > th) {
      canvas.drawRect(Rect.fromLTWH(0, 0, 3, size.height), clip);
    }
    if (h.red[255] > th || h.green[255] > th || h.blue[255] > th) {
      canvas.drawRect(Rect.fromLTWH(size.width - 3, 0, 3, size.height), clip);
    }
  }

  Path _fillPath(Int32List data, Size size, double norm) {
    final path = Path()..moveTo(0, size.height);
    for (int i = 0; i < 256; i++) {
      final x = i / 255.0 * size.width;
      final y =
          size.height - (data[i] / norm).clamp(0.0, 1.0) * (size.height - 4);
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  Path _strokePath(Int32List data, Size size, double norm) {
    final path = Path();
    for (int i = 0; i < 256; i++) {
      final x = i / 255.0 * size.width;
      final y =
          size.height - (data[i] / norm).clamp(0.0, 1.0) * (size.height - 4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_HistogramPainter old) => old.h != h;
}
