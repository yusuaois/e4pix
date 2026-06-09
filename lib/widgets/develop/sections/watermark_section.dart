import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/watermark_config.dart';
import '../../../state/providers.dart';
import '../tracked_slider.dart';
import 'shared.dart';

class WatermarkSection extends ConsumerWidget {
  const WatermarkSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(watermarkConfigProvider);
    final notifier = ref.read(watermarkConfigProvider.notifier);

    void set(WatermarkConfig v) => notifier.update(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 总开关 ──
        _SwitchTile(
          label: tr('watermarkEnable'),
          value: cfg.enabled,
          onChanged: (v) => set(cfg.copyWith(enabled: v)),
        ),
        if (!cfg.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              tr('watermarkDisabledHint'),
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),

        // ── 以下仅在水印开启时显示 ──
        if (cfg.enabled) ...[
          const SizedBox(height: 4),

          // ═══════ 背景 ═══════
          const SectionLabel(title: 'Background'),
          _DropdownTile<BackgroundType>(
            label: tr('watermarkBackgroundType'),
            value: cfg.backgroundType,
            items: const [
              DropdownMenuItem(
                value: BackgroundType.blurredOriginal,
                child: _DropLabel('Blurred Original'),
              ),
              DropdownMenuItem(
                value: BackgroundType.solidColor,
                child: _DropLabel('Solid Color'),
              ),
              DropdownMenuItem(
                value: BackgroundType.image,
                child: _DropLabel('Custom Image'),
              ),
            ],
            onChanged: (v) =>
                v != null ? set(cfg.copyWith(backgroundType: v)) : null,
          ),
          if (cfg.backgroundType == BackgroundType.solidColor)
            _ColorTile(
              label: tr('watermarkBgColor'),
              color: Color(cfg.backgroundColor),
              onChanged: (c) =>
                  set(cfg.copyWith(backgroundColor: c.toARGB32())),
            ),

          const SizedBox(height: 8),

          // ═══════ 布局 ═══════
          const SectionLabel(title: 'Layout'),
          DevelopSliderTile(
            label: tr('watermarkBlur'),
            value: cfg.blurRadius,
            min: 0,
            max: 100,
            suffix: ' px',
            onChanged: (v) => set(cfg.copyWith(blurRadius: v)),
          ),
          DevelopSliderTile(
            label: tr('watermarkBorderWidth'),
            value: cfg.borderWidth,
            min: 20,
            max: 200,
            suffix: ' px',
            onChanged: (v) => set(cfg.copyWith(borderWidth: v)),
          ),
          DevelopSliderTile(
            label: tr('watermarkImageScale'),
            value: cfg.imageScale,
            min: 0,
            max: 1.0,
            suffix: '%',
            precision: 0,
            onChanged: (v) => set(cfg.copyWith(imageScale: v)),
          ),

          const SizedBox(height: 8),

          // ═══════ 质感 ═══════
          const SectionLabel(title: 'Texture'),
          DevelopSliderTile(
            label: tr('watermarkCornerRadius'),
            value: cfg.cornerRadius,
            min: 0,
            max: 100,
            suffix: ' px',
            onChanged: (v) => set(cfg.copyWith(cornerRadius: v)),
          ),
          _ShadowIntensityTile(
            label: tr('watermarkShadowIntensity'),
            value: cfg.shadowIntensity,
            onChanged: (v) => set(cfg.copyWith(shadowIntensity: v)),
          ),

          const SizedBox(height: 8),

          // ═══════ 信息层位置 ═══════
          const SectionLabel(title: 'Info Position'),
          _DropdownTile<InfoPlacement>(
            label: tr('watermarkInfoPlacement'),
            value: cfg.infoPlacement,
            items: const [
              DropdownMenuItem(
                value: InfoPlacement.above,
                child: _DropLabel('Above Image'),
              ),
              DropdownMenuItem(
                value: InfoPlacement.below,
                child: _DropLabel('Below Image'),
              ),
            ],
            onChanged: (v) =>
                v != null ? set(cfg.copyWith(infoPlacement: v)) : null,
          ),

          const SizedBox(height: 8),

          // ═══════ Logo ═══════
          const SectionLabel(title: 'Logo'),
          _DropdownTile<String>(
            label: tr('watermarkLogoBrand'),
            value: cfg.logoBrand,
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: _DropLabel('None'),
              ),
              ...kAvailableLogoBrands.map(
                (b) => DropdownMenuItem<String>(
                  value: b,
                  child: _DropLabel(b[0].toUpperCase() + b.substring(1)),
                ),
              ),
            ],
            onChanged: (v) =>
                set(cfg.copyWith(logoBrand: v, clearLogo: v == null)),
          ),
          if (cfg.logoBrand != null) ...[
            DevelopSliderTile(
              label: tr('watermarkLogoSize'),
              value: cfg.logoSize,
              min: 0.1,
              max: 1.0,
              precision: 2,
              onChanged: (v) => set(cfg.copyWith(logoSize: v)),
            ),
            DevelopSliderTile(
              label: tr('watermarkLogoOpacity'),
              value: cfg.logoOpacity,
              min: 0.0,
              max: 1.0,
              precision: 2,
              onChanged: (v) => set(cfg.copyWith(logoOpacity: v)),
            ),
          ],

          const SizedBox(height: 8),

          // ═══════ Light / Dark ═══════
          const SectionLabel(title: 'Color Mode'),
          _SegmentedTile<WatermarkColorMode>(
            label: tr('watermarkColorMode'),
            value: cfg.colorMode,
            items: const [
              _SegItem(value: WatermarkColorMode.light, label: 'Light'),
              _SegItem(value: WatermarkColorMode.dark, label: 'Dark'),
            ],
            onChanged: (v) => set(cfg.copyWith(colorMode: v)),
          ),

          const SizedBox(height: 8),

          // ═══════ EXIF ═══════
          const SectionLabel(title: 'EXIF & Text'),
          _SwitchTile(
            label: tr('watermarkShowExif'),
            value: cfg.showExif,
            onChanged: (v) => set(cfg.copyWith(showExif: v)),
          ),
          if (cfg.showExif) ...[
            _FontFamilyTile(
              label: tr('watermarkFontFamily'),
              value: cfg.fontFamily,
              onChanged: (v) =>
                  set(cfg.copyWith(fontFamily: v, clearFontFamily: v == null)),
            ),
            DevelopSliderTile(
              label: tr('watermarkFontSize'),
              value: cfg.fontSize,
              min: 8,
              max: 36,
              suffix: ' pt',
              onChanged: (v) => set(cfg.copyWith(fontSize: v)),
            ),
            _FontWeightTile(
              label: tr('watermarkFontWeight'),
              value: cfg.fontWeightIndex,
              onChanged: (v) => set(cfg.copyWith(fontWeightIndex: v)),
            ),
            DevelopSliderTile(
              label: tr('watermarkTextOpacity'),
              value: cfg.textOpacity,
              min: 0.0,
              max: 1.0,
              precision: 2,
              onChanged: (v) => set(cfg.copyWith(textOpacity: v)),
            ),
            DevelopSliderTile(
              label: tr('watermarkTextPadding'),
              value: cfg.textPadding,
              min: 4,
              max: 60,
              suffix: ' px',
              onChanged: (v) => set(cfg.copyWith(textPadding: v)),
            ),
          ],

          const SizedBox(height: 12),
          // ── 重置按钮 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => notifier.reset(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr('reset')),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                foregroundColor: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

// ── 内部通用组件 ──

/// 开关 Tile
class _SwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// 下拉选择 Tile
class _DropdownTile<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T?>> items;
  final ValueChanged<T?>? onChanged;
  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T?>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: const Color(0xFF1E1E24),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 下拉选项文字
class _DropLabel extends StatelessWidget {
  final String text;
  const _DropLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 12));
  }
}

/// 颜色选择 Tile
class _ColorTile extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorTile({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          GestureDetector(
            onTap: () async {
              final c = await showDialog<Color>(
                context: context,
                builder: (_) => _ColorPickerDialog(initial: color),
              );
              if (c != null) onChanged(c);
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
            style: TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 简易颜色选择对话框
class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _r, _g, _b, _a;

  @override
  void initState() {
    super.initState();
    _r = widget.initial.r * 255;
    _g = widget.initial.g * 255;
    _b = widget.initial.b * 255;
    _a = widget.initial.a * 255;
  }

  Color get _color =>
      Color.fromARGB(_a.round(), _r.round(), _g.round(), _b.round());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Background Color'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
            const SizedBox(height: 16),
            _channel("R", _r, (v) => setState(() => _r = v)),
            _channel("G", _g, (v) => setState(() => _g = v)),
            _channel("B", _b, (v) => setState(() => _b = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _channel(String label, double val, ValueChanged<double> onV) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: val.clamp(0, 255),
              min: 0,
              max: 255,
              onChanged: onV,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            val.round().toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

/// 分段选择 Tile（如 Light/Dark）
class _SegmentedTile<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<_SegItem<T>> items;
  final ValueChanged<T> onChanged;
  const _SegmentedTile({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Row(
              children: items.map((item) {
                final selected = value == item.value;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(item.value),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegItem<T> {
  final T value;
  final String label;
  const _SegItem({required this.value, required this.label});
}

/// 阴影强度 Tile（带实时预览小样）
class _ShadowIntensityTile extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _ShadowIntensityTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scaled = (value * 100).round();
    final isNeutral = value == 0.0;
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
                onDoubleTap: () => onChanged(0.35),
                child: Text(
                  '$scaled%',
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
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 字体选择 Tile
class _FontFamilyTile extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _FontFamilyTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 常见跨平台字体列表
    const fonts = [
      null, // System Default
      'Roboto',
      'Open Sans',
      'Lato',
      'Montserrat',
      'Raleway',
      'Poppins',
      'Source Sans Pro',
      'Noto Sans',
      'Inter',
      'Courier New',
      'monospace',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: const Color(0xFF1E1E24),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  items: fonts.map((f) {
                    return DropdownMenuItem<String?>(
                      value: f,
                      child: Text(
                        f ?? 'System Default',
                        style: TextStyle(fontSize: 12, fontFamily: f),
                      ),
                    );
                  }).toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 字重选择 Tile
class _FontWeightTile extends StatelessWidget {
  final String label;
  final int value; // 0=w400 .. 4=w800
  final ValueChanged<int> onChanged;
  const _FontWeightTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  static const _weights = [
    (FontWeight.w400, 'Light'),
    (FontWeight.w500, 'Regular'),
    (FontWeight.w600, 'Medium'),
    (FontWeight.w700, 'Bold'),
    (FontWeight.w800, 'Heavy'),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = value.clamp(0, _weights.length - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Row(
              children: List.generate(_weights.length, (i) {
                final selected = i == idx;
                final (fw, name) = _weights[i];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(i),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: fw,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
