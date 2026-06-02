import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../render/full_pipeline_renderer.dart';
import '../state/interaction_state.dart';

class Histogram {
  final Int32List red, green, blue, luma;
  final Int32List hue;
  final int totalPixels;

  const Histogram._(
    this.red,
    this.green,
    this.blue,
    this.luma,
    this.hue,
    this.totalPixels,
  );

  factory Histogram.fromRgba(Uint8List px) {
    final r = Int32List(256), g = Int32List(256);
    final b = Int32List(256), l = Int32List(256);
    final hueBuf = Int32List(360);
    final n = px.length ~/ 4;
    for (int i = 0; i < px.length; i += 4) {
      final ri = px[i], gi = px[i + 1], bi = px[i + 2];
      r[ri]++;
      g[gi]++;
      b[bi]++;
      l[((ri * 54 + gi * 183 + bi * 19) >> 8).clamp(0, 255)]++;

      // Hue 计算
      final maxC = ri > gi ? (ri > bi ? ri : bi) : (gi > bi ? gi : bi);
      final minC = ri < gi ? (ri < bi ? ri : bi) : (gi < bi ? gi : bi);
      final delta = maxC - minC;
      if (delta > 12) {
        // 阈值：太灰的不计入（避免噪点污染色相分布）
        double hh;
        if (maxC == ri) {
          hh = ((gi - bi) / delta) % 6;
        } else if (maxC == gi) {
          hh = (bi - ri) / delta + 2;
        } else {
          hh = (ri - gi) / delta + 4;
        }
        int deg = (hh * 60).round();
        if (deg < 0) deg += 360;
        if (deg >= 360) deg -= 360;
        // 按饱和度加权：越鲜艳贡献越大
        hueBuf[deg] += delta;
      }
    }
    return Histogram._(r, g, b, l, hueBuf, n);
  }

  static final empty = Histogram._(_zero, _zero, _zero, _zero, _zero360, 0);
  static final _zero = Int32List(256);
  static final _zero360 = Int32List(360);
}

// Histogram
enum HistogramMode { rgb, luma, color }

class LiveHistogramPanel extends ConsumerStatefulWidget {
  final ui.FragmentProgram program;
  final ui.FragmentProgram maskProgram;
  final ui.Image? sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;

  const LiveHistogramPanel({
    super.key,
    required this.program,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
  });

  @override
  ConsumerState<LiveHistogramPanel> createState() => _LiveHistogramPanelState();
}

class _LiveHistogramPanelState extends ConsumerState<LiveHistogramPanel> {
  Histogram _hist = Histogram.empty;
  HistogramMode _mode = HistogramMode.rgb;
  Timer? _debounce;
  bool _computing = false;
  ProviderSubscription<bool>? _dragSub;
  static const _thumbDim = 256;

  @override
  void initState() {
    super.initState();
    // 拖动结束后强制重算一次
    _dragSub = ref.listenManual<bool>(isUserDraggingSliderProvider, (
      prev,
      next,
    ) {
      if (prev == true && next == false) _schedule();
    });
    _schedule();
  }

  @override
  void didUpdateWidget(LiveHistogramPanel old) {
    super.didUpdateWidget(old);
    if (old.params != widget.params ||
        old.sourceImage != widget.sourceImage ||
        old.lutTexture != widget.lutTexture ||
        old.lutTextureB != widget.lutTextureB ||
        old.curveTexture != widget.curveTexture) {
      // 拖动期间不算
      if (ref.read(isUserDraggingSliderProvider)) return;
      _schedule();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dragSub?.close();
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
      final scale =
          _thumbDim / (src.width > src.height ? src.width : src.height);
      final w = (src.width * scale).round().clamp(16, _thumbDim);
      final h = (src.height * scale).round().clamp(16, _thumbDim);

      if (!mounted || widget.sourceImage != captured) return;

      final rendered = await FullPipelineRenderer.render(
        developProgram: widget.program,
        maskProgram: widget.maskProgram,
        sourceImage: src,
        params: widget.params,
        lutTexture: widget.lutTexture,
        lutSize: widget.lutSize,
        lutTextureB: widget.lutTextureB,
        lutSizeB: widget.lutSizeB,
        curveTexture: widget.curveTexture,
        targetWidth: w,
        targetHeight: h,
      );
      try {
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
    return GestureDetector(
      onTap: () => setState(() {
        _mode = HistogramMode
            .values[(_mode.index + 1) % HistogramMode.values.length];
      }),
      child: Container(
        height: 110,
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0B10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _HistogramPainter(_hist, _mode)),
            ),
            // 模式标签
            Positioned(
              top: 4,
              right: 6,
              child: Text(
                switch (_mode) {
                  HistogramMode.rgb => 'RGB',
                  HistogramMode.luma => 'LUMA',
                  HistogramMode.color => 'COLOR',
                },
                style: TextStyle(
                  fontSize: 8.5,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Histogram Painter
class _HistogramPainter extends CustomPainter {
  final Histogram h;
  final HistogramMode mode;
  _HistogramPainter(this.h, this.mode);

  @override
  void paint(Canvas canvas, Size size) {
    if (h.totalPixels == 0) return;
    switch (mode) {
      case HistogramMode.rgb:
        _paintRgb(canvas, size);
        break;
      case HistogramMode.luma:
        _paintLuma(canvas, size);
        break;
      case HistogramMode.color:
        _paintColor(canvas, size);
        break;
    }
  }

  // RGB：三通道叠加
  void _paintRgb(Canvas canvas, Size size) {
    int peak = 1;
    for (int i = 1; i < 255; i++) {
      if (h.red[i] > peak) peak = h.red[i];
      if (h.green[i] > peak) peak = h.green[i];
      if (h.blue[i] > peak) peak = h.blue[i];
    }
    final norm = (peak * 1.15).toDouble();

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
    _clipWarn(canvas, size);
  }

  // Luma：单亮度填充
  void _paintLuma(Canvas canvas, Size size) {
    int peak = 1;
    for (int i = 1; i < 255; i++) {
      if (h.luma[i] > peak) peak = h.luma[i];
    }
    final norm = (peak * 1.15).toDouble();
    canvas.drawPath(
      _fillPath(h.luma, size, norm),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      _strokePath(h.luma, size, norm),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _clipWarn(canvas, size);
  }

  // Color：Hue 分布，每个柱用对应色相的颜色
  void _paintColor(Canvas canvas, Size size) {
    int peak = 1;
    for (int i = 0; i < 360; i++) {
      if (h.hue[i] > peak) peak = h.hue[i];
    }
    final norm = (peak * 1.1).toDouble();
    final barW = size.width / 360.0;
    for (int deg = 0; deg < 360; deg++) {
      final v = (h.hue[deg] / norm).clamp(0.0, 1.0);
      if (v <= 0) continue;
      final barH = v * (size.height - 4);
      final color = HSVColor.fromAHSV(1.0, deg.toDouble(), 0.8, 0.95).toColor();
      canvas.drawRect(
        Rect.fromLTWH(deg * barW, size.height - barH, barW + 0.5, barH),
        Paint()..color = color.withValues(alpha: 0.85),
      );
    }
  }

  void _clipWarn(Canvas canvas, Size size) {
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
  bool shouldRepaint(_HistogramPainter old) => old.h != h || old.mode != mode;
}
