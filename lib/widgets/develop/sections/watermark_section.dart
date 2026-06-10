import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/watermark_config.dart';
import '../../../services/watermark/watermark_asset_manager.dart';
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
          SectionLabel(title: tr('watermarkSectionBackground')),
          _DropdownTile<BackgroundType>(
            label: tr('watermarkBackgroundType'),
            value: cfg.backgroundType,
            items: [
              DropdownMenuItem(
                value: BackgroundType.blurredOriginal,
                child: _DropLabel(tr('watermarkBgBlurred')),
              ),
              DropdownMenuItem(
                value: BackgroundType.solidColor,
                child: _DropLabel(tr('watermarkBgSolid')),
              ),
              DropdownMenuItem(
                value: BackgroundType.image,
                child: _DropLabel(tr('watermarkBgCustomImage')),
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
          if (cfg.backgroundType == BackgroundType.image) ...[
            const SizedBox(height: 6),
            _ImportTile(
              label: tr('watermarkImportImage'),
              currentFile: cfg.customBackgroundPath,
              onImport: () async {
                final name =
                    await WatermarkAssetManager.pickAndSaveCustomImage();
                if (name != null) {
                  set(cfg.copyWith(customBackgroundPath: name));
                }
              },
              onClear: () => set(cfg.copyWith(clearCustomBg: true)),
            ),
          ],
          _DropdownTile<CanvasAspectRatio>(
            label: tr('watermarkCanvasRatio'),
            value: cfg.canvasAspectRatio,
            items: CanvasAspectRatio.values.map((r) {
              return DropdownMenuItem(
                value: r,
                child: _DropLabel(r.displayLabel),
              );
            }).toList(),
            onChanged: (v) =>
                v != null ? set(cfg.copyWith(canvasAspectRatio: v)) : null,
          ),

          const SizedBox(height: 8),

          // ═══════ 布局 ═══════
          SectionLabel(title: tr('watermarkSectionLayout')),
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
          SectionLabel(title: tr('watermarkSectionTexture')),
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
          SectionLabel(title: tr('watermarkSectionInfoPos')),
          _DropdownTile<InfoPlacement>(
            label: tr('watermarkInfoPlacement'),
            value: cfg.infoPlacement,
            items: [
              DropdownMenuItem(
                value: InfoPlacement.above,
                child: _DropLabel(tr('watermarkInfoAbove')),
              ),
              DropdownMenuItem(
                value: InfoPlacement.below,
                child: _DropLabel(tr('watermarkInfoBelow')),
              ),
              DropdownMenuItem(
                value: InfoPlacement.overlayTopLeft,
                child: _DropLabel(tr('watermarkInfoOverlayTL')),
              ),
              DropdownMenuItem(
                value: InfoPlacement.overlayTopRight,
                child: _DropLabel(tr('watermarkInfoOverlayTR')),
              ),
              DropdownMenuItem(
                value: InfoPlacement.overlayBottomLeft,
                child: _DropLabel(tr('watermarkInfoOverlayBL')),
              ),
              DropdownMenuItem(
                value: InfoPlacement.overlayBottomRight,
                child: _DropLabel(tr('watermarkInfoOverlayBR')),
              ),
            ],
            onChanged: (v) =>
                v != null ? set(cfg.copyWith(infoPlacement: v)) : null,
          ),

          const SizedBox(height: 8),

          // ═══════ Logo ═══════
          SectionLabel(title: tr('watermarkSectionLogo')),
          _DropdownTile<LogoSource>(
            label: tr('watermarkLogoSource'),
            value: cfg.logoSource,
            items: [
              DropdownMenuItem(
                value: LogoSource.builtin,
                child: _DropLabel(tr('watermarkLogoBuiltin')),
              ),
              DropdownMenuItem(
                value: LogoSource.custom,
                child: _DropLabel(tr('watermarkLogoCustom')),
              ),
            ],
            onChanged: (v) =>
                v != null ? set(cfg.copyWith(logoSource: v)) : null,
          ),
          if (cfg.logoSource == LogoSource.builtin) ...[
            _DropdownTile<String>(
              label: tr('watermarkLogoBrand'),
              value: cfg.logoBrand,
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: _DropLabel(tr('watermarkLogoNone')),
                ),
                ...kAvailableLogoBrands.map(
                  (b) => DropdownMenuItem<String>(
                    value: b,
                    child: _DropLabel(b[0].toUpperCase() + b.substring(1)),
                  ),
                ),
              ],
              onChanged: (v) =>
                  set(cfg.copyWith(logoBrand: v, clearLogoBrand: v == null)),
            ),
          ],
          if (cfg.logoSource == LogoSource.custom)
            _ImportTile(
              label: tr('watermarkImportLogo'),
              currentFile: cfg.customLogoPath,
              onImport: () async {
                final name =
                    await WatermarkAssetManager.pickAndSaveCustomImage();
                if (name != null) {
                  set(cfg.copyWith(customLogoPath: name));
                }
              },
              onClear: () => set(cfg.copyWith(clearCustomLogo: true)),
            ),
          if ((cfg.logoSource == LogoSource.builtin && cfg.logoBrand != null) ||
              (cfg.logoSource == LogoSource.custom &&
                  cfg.customLogoPath != null)) ...[
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
          SectionLabel(title: tr('watermarkSectionColorMode')),
          _SegmentedTile<WatermarkColorMode>(
            label: tr('watermarkColorMode'),
            value: cfg.colorMode,
            items: [
              _SegItem(
                value: WatermarkColorMode.light,
                label: tr('watermarkColorLight'),
              ),
              _SegItem(
                value: WatermarkColorMode.dark,
                label: tr('watermarkColorDark'),
              ),
            ],
            onChanged: (v) => set(cfg.copyWith(colorMode: v)),
          ),

          const SizedBox(height: 8),

          // ═══════ EXIF ═══════
          SectionLabel(title: tr('watermarkSectionExifText')),
          _SwitchTile(
            label: tr('watermarkShowExif'),
            value: cfg.showExif,
            onChanged: (v) => set(cfg.copyWith(showExif: v)),
          ),
          if (cfg.showExif) ...[
            _SegmentedTile<ExifMode>(
              label: tr('watermarkExifMode'),
              value: cfg.exifMode,
              items: [
                _SegItem(
                  value: ExifMode.auto,
                  label: tr('watermarkExifModeAuto'),
                ),
                _SegItem(
                  value: ExifMode.custom,
                  label: tr('watermarkExifModeCustom'),
                ),
              ],
              onChanged: (v) => set(cfg.copyWith(exifMode: v)),
            ),
            if (cfg.exifMode == ExifMode.custom)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: TextField(
                  controller:
                      TextEditingController(text: cfg.customExifText ?? '')
                        ..selection = TextSelection.fromPosition(
                          TextPosition(
                            offset: (cfg.customExifText ?? '').length,
                          ),
                        ),
                  onChanged: (v) {
                    set(
                      cfg.copyWith(
                        customExifText: v.isEmpty ? null : v,
                        clearCustomExif: v.isEmpty,
                      ),
                    );
                  },
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('watermarkExifCustomHint'),
                    hintStyle: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
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
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
      title: Text(tr('watermarkBgColorTitle')),
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
          child: Text(tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: Text(tr('ok')),
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
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
                        f ?? tr('watermarkFontSystem'),
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

  static List<(FontWeight, String)> _weights(BuildContext context) => [
    (FontWeight.w400, tr('watermarkWeightLight')),
    (FontWeight.w500, tr('watermarkWeightRegular')),
    (FontWeight.w600, tr('watermarkWeightMedium')),
    (FontWeight.w700, tr('watermarkWeightBold')),
    (FontWeight.w800, tr('watermarkWeightHeavy')),
  ];

  @override
  Widget build(BuildContext context) {
    final weights = _weights(context);
    final idx = value.clamp(0, weights.length - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(weights.length, (i) {
                final selected = i == idx;
                final (fw, name) = weights[i];
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

/// 导入文件 Tile（选择 + 清除）
class _ImportTile extends StatelessWidget {
  final String label;
  final String? currentFile;
  final Future<void> Function() onImport;
  final VoidCallback onClear;
  const _ImportTile({
    required this.label,
    required this.currentFile,
    required this.onImport,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: currentFile != null
                ? Row(
                    children: [
                      Icon(
                        Icons.image,
                        size: 14,
                        color: Colors.greenAccent.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currentFile!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onClear,
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  )
                : OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.file_upload_outlined, size: 14),
                    label: Text(
                      tr('import'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      foregroundColor: Colors.white.withValues(alpha: 0.7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
