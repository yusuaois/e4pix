import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/watermark_config.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../services/watermark/watermark_asset_manager.dart';
import '../../../../state/providers.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../../tracked_slider.dart';
import '../shared.dart';

class WatermarkSection extends ConsumerWidget {
  const WatermarkSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(watermarkConfigProvider);
    final notifier = ref.read(watermarkConfigProvider.notifier);
    void set(WatermarkConfig v) => notifier.update(v);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel(title: 'Watermark'),
          SwitchTile.tile(
            label: tr('watermarkEnable'),
            value: cfg.enabled,
            onChanged: (v) => set(cfg.copyWith(enabled: v)),
          ),
          if (cfg.enabled) ...[
            const SizedBox(height: 4),
            _buildBackgroundSection(context, cfg, set),
            const SizedBox(height: 8),
            _buildLayoutSection(cfg, set),
            const SizedBox(height: 8),
            _buildTextureSection(cfg, set),
            const SizedBox(height: 8),
            _buildInfoPositionSection(cfg, set),
            const SizedBox(height: 8),
            _buildLogoSection(cfg, set),
            const SizedBox(height: 8),
            _buildColorModeSection(cfg, set),
            const SizedBox(height: 8),
            _buildExifSection(context, cfg, set),
            const SizedBox(height: 12),
            _buildResetButton(() => notifier.reset()),
            const SizedBox(height: 24),
          ] else
            _buildDisabledHint(),
        ],
      ),
    );
  }

  Widget _buildDisabledHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Text(
        tr('watermarkDisabledHint'),
        style: AppTypography.bodySmall.copyWith(color: AppColors.disabledText),
      ),
    );
  }

  Widget _buildBackgroundSection(
    BuildContext context,
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            color: cfg.backgroundColor,
            onChanged: (c) => set(cfg.copyWith(backgroundColor: c)),
          ),
        if (cfg.backgroundType == BackgroundType.image) ...[
          const SizedBox(height: 6),
          _ImportTile(
            label: tr('watermarkImportImage'),
            currentFile: cfg.customBackgroundPath,
            onImport: () async {
              final name = await WatermarkAssetManager.pickAndSaveCustomImage();
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
      ],
    );
  }

  Widget _buildLayoutSection(
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          fractionDigits: 0,
          onChanged: (v) => set(cfg.copyWith(imageScale: v)),
        ),
      ],
    );
  }

  Widget _buildTextureSection(
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
  }

  Widget _buildInfoPositionSection(
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
  }

  Widget _buildLogoSection(
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          onChanged: (v) => v != null ? set(cfg.copyWith(logoSource: v)) : null,
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
              final name = await WatermarkAssetManager.pickAndSaveCustomImage();
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
            fractionDigits: 2,
            onChanged: (v) => set(cfg.copyWith(logoSize: v)),
          ),
          DevelopSliderTile(
            label: tr('watermarkLogoOpacity'),
            value: cfg.logoOpacity,
            min: 0.0,
            max: 1.0,
            fractionDigits: 2,
            onChanged: (v) => set(cfg.copyWith(logoOpacity: v)),
          ),
        ],
      ],
    );
  }

  Widget _buildColorModeSection(
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
  }

  Widget _buildExifSection(
    BuildContext context,
    WatermarkConfig cfg,
    void Function(WatermarkConfig) set,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: tr('watermarkSectionExifText')),
        SwitchTile.tile(
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
          // EXIF 字段选择（仅自动模式）
          if (cfg.exifMode == ExifMode.auto)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: ExifField.values.map((field) {
                  final selected =
                      cfg.enabledExifFields.isEmpty ||
                      cfg.enabledExifFields.contains(field);
                  return _ExifFieldChip(
                    label: field.displayLabelKey.tr(),
                    selected: selected,
                    onTap: () {
                      final s = Set<ExifField>.from(cfg.enabledExifFields);
                      if (cfg.enabledExifFields.isEmpty) {
                        s.addAll(ExifField.values);
                        s.remove(field);
                      } else if (selected) {
                        s.remove(field);
                        if (s.isEmpty) {
                          set(cfg.copyWith(clearExifFields: true));
                          return;
                        }
                      } else {
                        s.add(field);
                        if (s.length == ExifField.values.length) {
                          set(cfg.copyWith(clearExifFields: true));
                          return;
                        }
                      }
                      set(cfg.copyWith(enabledExifFields: s));
                    },
                  );
                }).toList(),
              ),
            ),
          if (cfg.exifMode == ExifMode.custom)
            _ExifTextField(
              initialText: cfg.customExifText,
              onChanged: (v) {
                set(
                  cfg.copyWith(
                    customExifText: v.isEmpty ? null : v,
                    clearCustomExif: v.isEmpty,
                  ),
                );
              },
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
            fractionDigits: 2,
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
      ],
    );
  }

  Widget _buildResetButton(void Function() onReset) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: onReset,
        icon: const Icon(Icons.refresh, size: 16),
        label: Text(tr('reset')),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.lightBorder),
          foregroundColor: AppColors.mediumText,
        ),
      ),
    );
  }
}

// ── 内部通用组件 ──

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
              style: AppTypography.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.activeBg),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T?>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: AppColors.panelBg,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
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
    return Text(text, style: AppTypography.bodyLarge);
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
              style: AppTypography.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildColorPicker(context),
          const SizedBox(width: 10),
          _buildHexLabel(),
        ],
      ),
    );
  }

  Widget _buildColorPicker(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final newColor = await showColorPickerDialog(
          context,
          color,
          title: const SizedBox.shrink(),
          width: 40,
          height: 40,
          borderRadius: 4,
          spacing: 5,
          runSpacing: 5,
          wheelDiameter: 165,
          showColorCode: true,
          colorCodeHasColor: true,
          showColorName: true,
          showMaterialName: true,
          enableOpacity: false,
          enableTonalPalette: false,
          pickersEnabled: const <ColorPickerType, bool>{
            ColorPickerType.both: false,
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.bw: false,
            ColorPickerType.custom: false,
            ColorPickerType.wheel: true,
          },
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 320),
        );
        onChanged(newColor);
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.dividerLine),
        ),
      ),
    );
  }

  Widget _buildHexLabel() {
    return Text(
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
      style: AppTypography.labelMedium.copyWith(
        fontFamily: 'monospace',
        color: AppColors.faintText,
      ),
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
              style: AppTypography.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Row(
              children: items
                  .map(
                    (item) => _SegButton(
                      item: item,
                      selected: value == item.value,
                      onTap: () => onChanged(item.value),
                    ),
                  )
                  .toList(),
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

class _SegButton<T> extends StatelessWidget {
  final _SegItem<T> item;
  final bool selected;
  final VoidCallback onTap;
  const _SegButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.2)
                : AppColors.subtleBorder,
            border: Border.all(
              color: selected ? primary : AppColors.dividerLine,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            item.label,
            style: AppTypography.bodyMedium.copyWith(
              color: selected ? primary : AppColors.mediumText,
            ),
          ),
        ),
      ),
    );
  }
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
              Expanded(child: Text(label, style: AppTypography.titleSmall)),
              GestureDetector(
                onDoubleTap: () => onChanged(0.35),
                child: Text(
                  '$scaled%',
                  style: AppTypography.bodyMedium.copyWith(
                    fontFamily: 'monospace',
                    color: isNeutral
                        ? AppColors.disabledText
                        : AppColors.activeValue,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTypography.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(child: _buildFontDropdown()),
        ],
      ),
    );
  }

  Widget _buildFontDropdown() {
    const fonts = [
      null,
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
    return Container(
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.activeBg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.panelBg,
          style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
          items: fonts.map((f) {
            return DropdownMenuItem<String?>(
              value: f,
              child: Text(
                f ?? tr('watermarkFontSystem'),
                style: AppTypography.bodyLarge.copyWith(fontFamily: f),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// 自定义 EXIF 文本输入框
class _ExifTextField extends StatefulWidget {
  final String? initialText;
  final ValueChanged<String> onChanged;

  const _ExifTextField({required this.initialText, required this.onChanged});

  @override
  State<_ExifTextField> createState() => _ExifTextFieldState();
}

class _ExifTextFieldState extends State<_ExifTextField> {
  late final TextEditingController _controller;
  bool _isInternalUpdate = false;

  @override
  void initState() {
    super.initState();
    final text = widget.initialText ?? '';
    _controller = TextEditingController(text: text);
    if (text.isNotEmpty) {
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    }
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(_ExifTextField old) {
    super.didUpdateWidget(old);
    if (widget.initialText != old.initialText &&
        widget.initialText != _controller.text) {
      _isInternalUpdate = true;
      final text = widget.initialText ?? '';
      _controller.text = text;
      if (text.isNotEmpty) {
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
      }
      _isInternalUpdate = false;
    }
  }

  void _onControllerChanged() {
    if (!_isInternalUpdate) {
      widget.onChanged(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _controller,
        style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('watermarkExifCustomHint'),
          hintStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.disabledText,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: AppColors.faintBorder),
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
              style: AppTypography.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(weights.length, (i) {
                final selected = i == idx;
                final (fw, name) = weights[i];
                return _WeightButton(
                  name: name,
                  fontWeight: fw,
                  selected: selected,
                  onTap: () => onChanged(i),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightButton extends StatelessWidget {
  final String name;
  final FontWeight fontWeight;
  final bool selected;
  final VoidCallback onTap;
  const _WeightButton({
    required this.name,
    required this.fontWeight,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.2)
                : AppColors.subtleBorder,
            border: Border.all(
              color: selected ? primary : AppColors.dividerLine,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: AppTypography.labelSmall.copyWith(
              fontWeight: fontWeight,
              color: selected ? primary : AppColors.mediumText,
            ),
          ),
        ),
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
              style: AppTypography.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: currentFile != null
                ? _buildFileInfo()
                : _buildImportButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfo() {
    return Row(
      children: [
        Icon(
          Icons.image,
          size: 14,
          color: AppColors.semanticSuccess.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            currentFile!,
            style: AppTypography.labelMedium.copyWith(
              fontFamily: 'monospace',
              color: AppColors.mediumText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onClear,
          child: Icon(Icons.close, size: 14, color: AppColors.disabledText),
        ),
      ],
    );
  }

  Widget _buildImportButton() {
    return OutlinedButton.icon(
      onPressed: onImport,
      icon: const Icon(Icons.file_upload_outlined, size: 14),
      label: Text(tr('import'), style: AppTypography.bodySmall),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: AppColors.lightBorder),
        foregroundColor: AppColors.mediumText,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
    );
  }
}

// EXIF 字段选择 Chip

class _ExifFieldChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ExifFieldChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
              : AppColors.subtleBorder,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                : AppColors.activeBg,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : AppColors.faintText,
          ),
        ),
      ),
    );
  }
}
