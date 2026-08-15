import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/models/adjustment_params.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../render/cache/mask_cache.dart';
import '../../utils/debouncer.dart';
import '../../utils/shader_pass_util.dart';
import '../../state/providers.dart';

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
  final double? height;
  final EdgeInsetsGeometry? margin;

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
    this.height,
    this.margin,
  });

  @override
  ConsumerState<LiveHistogramPanel> createState() => _LiveHistogramPanelState();
}

class _LiveHistogramPanelState extends ConsumerState<LiveHistogramPanel> {
  Histogram _hist = Histogram.empty;
  HistogramMode _mode = HistogramMode.rgb;
  final _debounce = Debouncer();
  bool _computing = false;
  ProviderSubscription<bool>? _dragSub;
  // 128px 缩略图足够直方图统计（256 bins × 128px = 2px/bin 平均）
  // 相比 256px 减少 4× 像素数，大幅降低渲染和回读开销
  static const _thumbDim = 128;
  // develop pass 缓存：同一组基础参数下直方图只需重跑 mask/sharpen 等后续 pass
  final _developCache = DevelopPassCache();

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
    _debounce.dispose();
    _dragSub?.close();
    _developCache.dispose();
    super.dispose();
  }

  void _schedule() {
    // 50ms 防抖：直方图不需要逐帧更新，略长于预览渲染周期（33ms）减少 GPU 争抢
    _debounce.run(const Duration(milliseconds: 50), _recompute);
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

      final result = await FullPipelineRenderer.render(
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
        developCache: _developCache,
      );
      final rendered = result.finalImage;
      result.developOutput?.dispose();
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
    } on DisposedImageException {
      // 纹理已 dispose，跳过本帧
      debugPrint('[Histogram] Skipped compute: source image disposed');
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
        clipBehavior: Clip.antiAlias,
        height: widget.height ?? 110,
        width: double.infinity,
        margin: widget.margin ?? const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: AppColors.scaffoldBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.subtleBorder),
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
                style: AppTypography.labelSmall.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                  color: AppColors.disabledText,
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
    _drawSubtleGrid(canvas, size);
    int peak = 1;
    for (int i = 0; i < 256; i++) {
      if (h.red[i] > peak) peak = h.red[i];
      if (h.green[i] > peak) peak = h.green[i];
      if (h.blue[i] > peak) peak = h.blue[i];
    }
    final norm = (peak * 1.25).toDouble();

    const fillAlpha = 0.20;
    canvas.drawPath(
      _fillPath(h.blue, size, norm),
      Paint()..color = AppColors.histBlue.withValues(alpha: fillAlpha),
    );
    canvas.drawPath(
      _fillPath(h.green, size, norm),
      Paint()..color = AppColors.histGreen.withValues(alpha: fillAlpha),
    );
    canvas.drawPath(
      _fillPath(h.red, size, norm),
      Paint()..color = AppColors.histRed.withValues(alpha: fillAlpha),
    );

    const strokeAlpha = 0.95;
    const strokeWidth = 1.6;

    void drawStroke(Int32List data, Color color) {
      canvas.drawPath(
        _strokePath(data, size, norm),
        Paint()
          ..color = color.withValues(alpha: strokeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..isAntiAlias = true,
      );
    }

    drawStroke(h.red, AppColors.histRed);
    drawStroke(h.green, AppColors.histGreen);
    drawStroke(h.blue, AppColors.histBlue);

    _clipWarn(canvas, size);
  }

  // Luma：单亮度填充
  void _paintLuma(Canvas canvas, Size size) {
    _drawSubtleGrid(canvas, size);
    int peak = 1;
    for (int i = 0; i < 256; i++) {
      if (h.luma[i] > peak) peak = h.luma[i];
    }
    final norm = (peak * 1.25).toDouble();
    canvas.drawPath(
      _fillPath(h.luma, size, norm),
      Paint()..color = AppColors.faintText.withValues(alpha: 0.7),
    );
    canvas.drawPath(
      _strokePath(h.luma, size, norm),
      Paint()
        ..color = AppColors.prominentText
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    _clipWarn(canvas, size);
  }

  // Color：Hue 分布，每个柱用对应色相的颜色
  void _paintColor(Canvas canvas, Size size) {
    _drawSubtleGrid(canvas, size);
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
      final darkColor = HSVColor.fromAHSV(
        1.0,
        deg.toDouble(),
        0.9,
        0.4,
      ).toColor();
      canvas.drawRect(
        Rect.fromLTWH(deg * barW, size.height - barH, barW + 0.5, barH),
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        Rect.fromLTWH(deg * barW, size.height - barH, barW + 0.5, barH),
        Paint()
          ..color = darkColor.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  void _drawSubtleGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.6;

    for (final frac in [0.25, 0.5, 0.75]) {
      final x = frac * size.width;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), gridPaint);
    }
  }

  void _clipWarn(Canvas canvas, Size size) {
    final clip = Paint()
      ..color = AppColors.semanticError.withValues(alpha: 0.65);
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
