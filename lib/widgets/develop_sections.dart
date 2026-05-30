import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/lut_formats.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/hsl_bands.dart';
import '../core/models/rgb_curves.dart';
import '../core/models/tone_curve.dart';
import '../services/lut_library.dart';
import '../state/lut_library_state.dart';
import '../state/params_state.dart';
import '../state/render_state.dart';
import 'tracked_slider.dart';

// 通用滑块 tile
class DevelopSliderTile extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final String suffix;
  final int precision;

  const DevelopSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
    this.precision = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasZeroDetent = min < 0 && max > 0;
    final zeroValue = hasZeroDetent ? 0.0 : (min + max) / 2;
    final isNeutral = (value - zeroValue).abs() < 0.001;
    final display = value.toStringAsFixed(precision);
    final sign = !hasZeroDetent || value <= 0 ? '' : '+';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12.5)),
              ),
              GestureDetector(
                onDoubleTap: () => onChanged(zeroValue),
                child: Text(
                  '$sign$display$suffix',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: isNeutral
                        ? Colors.white.withValues(alpha: 0.4)
                        : Colors.greenAccent.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: TrackedSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// Section 标签
class SectionLabel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionLabel({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.4),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

// Light Section
class LightSection extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const LightSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Light'),
        DevelopSliderTile(
          label: tr("exposure"),
          value: p.exposure,
          min: -5,
          max: 5,
          onChanged: (v) => onChanged(p.copyWith(exposure: v)),
          suffix: ' EV',
          precision: 2,
        ),
        DevelopSliderTile(
          label: tr("contrast"),
          value: p.contrast,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(contrast: v)),
        ),
        DevelopSliderTile(
          label: tr("highlight"),
          value: p.highlights,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(highlights: v)),
        ),
        DevelopSliderTile(
          label: tr("shadow"),
          value: p.shadows,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(shadows: v)),
        ),
        DevelopSliderTile(
          label: tr("white"),
          value: p.whites,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(whites: v)),
        ),
        DevelopSliderTile(
          label: tr("black"),
          value: p.blacks,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(blacks: v)),
        ),
      ],
    );
  }
}

// White Balance + Color Section
class WhiteBalanceColorSection extends StatelessWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;
  const WhiteBalanceColorSection({
    super.key,
    required this.params,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'White Balance'),
        DevelopSliderTile(
          label: tr("whiteBalance"),
          value: p.temperature.toDouble(),
          min: 2000,
          max: 12000,
          onChanged: (v) => onChanged(p.copyWith(temperature: v.round())),
          suffix: ' K',
        ),
        DevelopSliderTile(
          label: tr("tint"),
          value: p.tint,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(tint: v)),
        ),
        const SectionLabel(title: 'Color'),
        DevelopSliderTile(
          label: tr("saturation"),
          value: p.saturation,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(saturation: v)),
        ),
        DevelopSliderTile(
          label: tr("vibrance"),
          value: p.vibrance,
          min: -100,
          max: 100,
          onChanged: (v) => onChanged(p.copyWith(vibrance: v)),
        ),
      ],
    );
  }
}

// Curve
class CurveSection extends ConsumerStatefulWidget {
  const CurveSection({super.key});
  @override
  ConsumerState<CurveSection> createState() => _CurveSectionState();
}

class _CurveSectionState extends ConsumerState<CurveSection> {
  int _channel = 0; // 0主 1R 2G 3B
  int? _dragIndex;

  ToneCurve _curveOf(RgbCurves c) => switch (_channel) {
    1 => c.red,
    2 => c.green,
    3 => c.blue,
    _ => c.master,
  };

  RgbCurves _withChannel(RgbCurves c, ToneCurve nc) => switch (_channel) {
    1 => c.copyWith(red: nc),
    2 => c.copyWith(green: nc),
    3 => c.copyWith(blue: nc),
    _ => c.copyWith(master: nc),
  };

  Color _channelColor(BuildContext ctx) => switch (_channel) {
    1 => const Color(0xFFE5534B),
    2 => const Color(0xFF4CAF50),
    3 => const Color(0xFF5B8DEF),
    _ => Theme.of(ctx).colorScheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(currentParamsNotifierProvider);
    final curves = params.curves;
    final curve = _curveOf(curves);
    final lineColor = _channelColor(context);

    void commit(ToneCurve next) {
      ref
          .read(currentParamsNotifierProvider.notifier)
          .update(params.copyWith(curves: _withChannel(curves, next)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: '曲线'),
        const SizedBox(height: 8),
        // 通道切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _chTab('RGB', 0, Theme.of(context).colorScheme.primary),
              _chTab('R', 1, const Color(0xFFE5534B)),
              _chTab('G', 2, const Color(0xFF4CAF50)),
              _chTab('B', 3, const Color(0xFF5B8DEF)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapUp: (d) => _onTapUp(d, size, curve, commit),
                  onPanStart: (d) => _onPanStart(d, size, curve),
                  onPanUpdate: (d) => _onPanUpdate(d, size, curve, commit),
                  onPanEnd: (_) => _dragIndex = null,
                  onLongPressStart: (d) =>
                      _onLongPress(d.localPosition, size, curve, commit),
                  child: CustomPaint(
                    painter: _CurvePainter(curve: curve, lineColor: lineColor),
                    size: size,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr("curveHint"),
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              TextButton(
                onPressed: curve.isIdentity
                    ? null
                    : () => commit(ToneCurve.identity),
                child: Text(tr("reset"), style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chTab(String label, int ch, Color color) {
    final sel = _channel == ch;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _channel = ch),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: sel ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: sel ? color : Colors.white.withValues(alpha: 0.12),
              width: sel ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: sel ? color : Colors.white.withValues(alpha: 0.6),
              fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Offset2 _toNorm(Offset local, Size size) => Offset2(
    (local.dx / size.width).clamp(0.0, 1.0),
    (1 - local.dy / size.height).clamp(0.0, 1.0),
  );
  Offset _toScreen(Offset2 p, Size size) =>
      Offset(p.x * size.width, (1 - p.y) * size.height);
  int? _hitTest(Offset local, Size size, ToneCurve curve) {
    const r = 22.0;
    for (int i = 0; i < curve.points.length; i++) {
      if ((_toScreen(curve.points[i], size) - local).distance < r) return i;
    }
    return null;
  }

  void _onTapUp(
    TapUpDetails d,
    Size size,
    ToneCurve curve,
    void Function(ToneCurve) commit,
  ) {
    if (_hitTest(d.localPosition, size, curve) != null) return;
    final n = _toNorm(d.localPosition, size);
    final pts = [...curve.points, Offset2(n.x, n.y)]
      ..sort((a, b) => a.x.compareTo(b.x));
    commit(ToneCurve(pts));
  }

  void _onPanStart(DragStartDetails d, Size size, ToneCurve curve) {
    _dragIndex = _hitTest(d.localPosition, size, curve);
  }

  void _onPanUpdate(
    DragUpdateDetails d,
    Size size,
    ToneCurve curve,
    void Function(ToneCurve) commit,
  ) {
    final i = _dragIndex;
    if (i == null) return;
    final n = _toNorm(d.localPosition, size);
    final pts = [...curve.points];
    final isFirst = i == 0, isLast = i == pts.length - 1;
    double nx;
    if (isFirst) {
      nx = 0.0;
    } else if (isLast) {
      nx = 1.0;
    } else {
      nx = n.x.clamp(pts[i - 1].x + 0.01, pts[i + 1].x - 0.01);
    }
    pts[i] = Offset2(nx, n.y);
    commit(ToneCurve(pts));
  }

  void _onLongPress(
    Offset local,
    Size size,
    ToneCurve curve,
    void Function(ToneCurve) commit,
  ) {
    final hit = _hitTest(local, size, curve);
    if (hit == null || hit == 0 || hit == curve.points.length - 1) return;
    final pts = [...curve.points]..removeAt(hit);
    commit(ToneCurve(pts));
  }
}

class _CurvePainter extends CustomPainter {
  final ToneCurve curve;
  final Color lineColor;
  _CurvePainter({required this.curve, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // 背景
    final bg = Paint()..color = const Color(0xFF0E0E12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      bg,
    );

    // 网格（4×4）
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final x = w * i / 4;
      final y = h * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
    // 对角参考线
    final diag = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h), Offset(w, 0), diag);

    // 曲线（用 256 点 LUT 画）
    final lut = curve.toLut(count: 128);
    final path = Path();
    for (int i = 0; i < lut.length; i++) {
      final x = w * i / (lut.length - 1);
      final y = h * (1 - lut[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // 控制点
    for (final p in curve.points) {
      final c = Offset(p.x * w, (1 - p.y) * h);
      canvas.drawCircle(c, 6, Paint()..color = const Color(0xFF0E0E12));
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(c, 2.5, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.curve != curve || old.lineColor != lineColor;
}

// HSL Section
class HslSection extends StatefulWidget {
  final HslBands bands;
  final ValueChanged<HslBands> onChanged;
  const HslSection({super.key, required this.bands, required this.onChanged});

  @override
  State<HslSection> createState() => _HslSectionState();
}

class _HslSectionState extends State<HslSection> {
  int _mode = 0; // 0=Hue, 1=Sat, 2=Lum

  static const _bandColors = [
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
  ];
  final _bandLabels = [
    tr("red"),
    tr("orange"),
    tr("yellow"),
    tr("green"),
    tr("cyan"),
    tr("blue"),
    tr("purple"),
    tr("magenta"),
  ];

  List<double> _values() => switch (_mode) {
    0 => widget.bands.hues,
    1 => widget.bands.sats,
    _ => widget.bands.lums,
  };

  void _setValue(int index, double v) {
    final updated = switch (_mode) {
      0 => widget.bands.setHue(index, v),
      1 => widget.bands.setSat(index, v),
      _ => widget.bands.setLum(index, v),
    };
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final values = _values();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          title: 'HSL / Color',
          trailing: !widget.bands.isNeutral
              ? GestureDetector(
                  onTap: () => widget.onChanged(HslBands.neutral),
                  child: Text(
                    'reset',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
            segments: [
              ButtonSegment(value: 0, label: Text(tr("hue"))),
              ButtonSegment(value: 1, label: Text(tr("sat"))),
              ButtonSegment(value: 2, label: Text(tr("lum"))),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          8,
          (i) => _BandRow(
            color: _bandColors[i],
            label: _bandLabels[i],
            value: values[i],
            onChanged: (v) => _setValue(i, v),
          ),
        ),
      ],
    );
  }
}

class _BandRow extends StatelessWidget {
  final Color color;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _BandRow({
    required this.color,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isNeutral = value.abs() < 0.01;
    final sign = value > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 11.5)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: TrackedSlider(
                value: value.clamp(-100.0, 100.0),
                min: -100,
                max: 100,
                onChanged: onChanged,
              ),
            ),
          ),
          GestureDetector(
            onDoubleTap: () => onChanged(0),
            child: SizedBox(
              width: 36,
              child: Text(
                '$sign${value.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: isNeutral
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.greenAccent.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// LUT Section
// LUT Section — 双槽 (A → B 串联)，自取 provider
class LutSection extends ConsumerWidget {
  const LutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lut = ref.watch(lutNotifierProvider);
    final params = ref.watch(currentParamsNotifierProvider);
    final library = ref.watch(lutLibraryNotifierProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'LUT'),
        const SizedBox(height: 4),
        _LutSlot(
          slot: 0,
          label: 'LUT A',
          lutName: lut.nameA,
          intensity: params.lutIntensity,
          library: library,
        ),
        const SizedBox(height: 10),
        _LutSlot(
          slot: 1,
          label: 'LUT B',
          lutName: lut.nameB,
          intensity: params.lutIntensityB,
          library: library,
        ),
      ],
    );
  }
}

class _LutSlot extends ConsumerWidget {
  final int slot; // 0 = A, 1 = B
  final String label;
  final String? lutName;
  final double intensity;
  final List<LutEntry> library;

  const _LutSlot({
    required this.slot,
    required this.label,
    required this.lutName,
    required this.intensity,
    required this.library,
  });

  // 反查当前选中 entry：比较「不带扩展名的文件名」，兼容 .cube / .vlt
  LutEntry? _findSelected() {
    if (lutName == null) return null;
    final target = _stripExt(lutName!).toLowerCase();
    for (final e in library) {
      if (e.name.toLowerCase() == target) return e;
    }
    return null;
  }

  static String _stripExt(String n) {
    final dot = n.lastIndexOf('.');
    return dot < 0 ? n : n.substring(0, dot);
  }

  bool get _isVlt => lutName != null && LutFormats.isVlt(lutName!);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = lutName != null;
    final selected = _findSelected();

    Future<void> onSelect(LutEntry? entry) async {
      if (entry == null) {
        ref.read(lutNotifierProvider.notifier).clear(slot: slot);
      } else {
        await ref
            .read(lutNotifierProvider.notifier)
            .loadFromCubeFile(entry.filePath, slot: slot);
      }
    }

    Future<void> onImport() async {
      final entry = await ref
          .read(lutLibraryNotifierProvider.notifier)
          .importFromFile();
      if (entry != null) {
        await ref
            .read(lutNotifierProvider.notifier)
            .loadFromCubeFile(entry.filePath, slot: slot);
      }
    }

    Future<void> onDelete(LutEntry entry) async {
      // 若该 entry 正用于任一槽，先清该槽
      final cur = ref.read(lutNotifierProvider);
      if (_stripExt(cur.nameA ?? '').toLowerCase() ==
          entry.name.toLowerCase()) {
        ref.read(lutNotifierProvider.notifier).clear(slot: 0);
      }
      if (_stripExt(cur.nameB ?? '').toLowerCase() ==
          entry.name.toLowerCase()) {
        ref.read(lutNotifierProvider.notifier).clear(slot: 1);
      }
      await ref.read(lutLibraryNotifierProvider.notifier).delete(entry);
    }

    void onIntensityChanged(double v) {
      final p = ref.read(currentParamsNotifierProvider);
      final np = slot == 0
          ? p.copyWith(lutIntensity: v)
          : p.copyWith(lutIntensityB: v);
      ref.read(currentParamsNotifierProvider.notifier).update(np);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<LutEntry?>(
                    isExpanded: true,
                    value: selected,
                    hint: Text(
                      library.isEmpty ? tr("notImportedLUT") : tr("notChosen"),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    iconSize: 16,
                    items: [
                      DropdownMenuItem<LutEntry?>(
                        value: null,
                        child: Text(
                          tr("notChosen"),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      ...library.map(
                        (entry) => DropdownMenuItem<LutEntry?>(
                          value: entry,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.name,
                                  style: const TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                entry.ext.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontFamily: 'monospace',
                                  color: entry.ext == 'vlt'
                                      ? Colors.orangeAccent.withValues(
                                          alpha: 0.7,
                                        )
                                      : Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    onChanged: onSelect,
                  ),
                ),
              ),
              if (selected != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: tr("deleteCurrentLUT"),
                  onPressed: () =>
                      _confirmDelete(context, ref, selected, onDelete),
                ),
              IconButton(
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: tr("importCube"),
                onPressed: onImport,
              ),
            ],
          ),
        ),
        // .vlt 提示
        if (_isVlt)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Text(
              tr("lutVltHint"), // "适用于 V-Log 素材"
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.orangeAccent.withValues(alpha: 0.75),
              ),
            ),
          ),
        if (loaded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 64,
                  child: Text('Intensity', style: TextStyle(fontSize: 11.5)),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: TrackedSlider(
                      value: intensity.clamp(0.0, 1.0),
                      onChanged: onIntensityChanged,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(intensity * 100).round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Colors.greenAccent.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext ctx,
    WidgetRef ref,
    LutEntry entry,
    Future<void> Function(LutEntry) onDelete,
  ) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(tr('deleteLUT')),
        content: Text(tr('confirmDeleteLUT', args: [entry.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr("cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(tr("delete")),
          ),
        ],
      ),
    );
    if (ok == true) await onDelete(entry);
  }
}
