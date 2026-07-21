import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../state/providers.dart';
import '../app/theme_color_picker.dart';

class ThemeTiles extends ConsumerWidget {
  final BorderRadius? tileBorderRadius;
  const ThemeTiles({super.key, this.tileBorderRadius});

  static const List<Color> _presets = [
    Color(0xFF4CAF50), // 绿色（默认）
    Color(0xFF2196F3), // 蓝色
    Color(0xFF6750A4), // 紫罗兰色
    Color(0xFFE91E63), // 粉红色
    Color(0xFFFF9800), // 橙色
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dynamicEnabled = ref.watch(dynamicColorEnabledProvider);
    final seed = ref.watch(seedColorProvider);
    final isPreset = _presets.any((c) => c.toARGB32() == seed);

    return Column(
      children: [
        SwitchListTile(
          shape: dynamicEnabled && tileBorderRadius != null
              ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
              : null,
          secondary: const Icon(Icons.palette_outlined, size: 20),
          title: Text(
            tr("settingsDynamicColor"),
            style: AppTypography.titleMedium,
          ),
          subtitle: Text(
            tr("settingsDynamicColorHint"),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          value: dynamicEnabled,
          onChanged: (v) =>
              ref.read(dynamicColorEnabledProvider.notifier).set(v),
        ),
        if (!dynamicEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
            child: Row(
              children: [
                for (final c in _presets) ...[
                  Swatch(
                    color: c,
                    selected: seed == c.toARGB32(),
                    onTap: () =>
                        ref.read(seedColorProvider.notifier).set(c.toARGB32()),
                  ),
                  const SizedBox(width: 10),
                ],
                Swatch.wheel(
                  selected: !isPreset,
                  current: Color(seed),
                  onTap: () async {
                    final picked = await showDialog<Color>(
                      context: context,
                      builder: (_) => ThemeColorWheelDialog(
                        initial: Color(seed),
                        isGrayscale: false,
                      ),
                    );
                    if (picked != null) {
                      ref
                          .read(seedColorProvider.notifier)
                          .set(picked.toARGB32());
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isWheel;
  final Color? current;

  const Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  }) : isWheel = false,
       current = null;

  const Swatch.wheel({
    super.key,
    required this.selected,
    required this.current,
    required this.onTap,
  }) : color = Colors.transparent,
       isWheel = true;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isWheel ? null : color,
          shape: BoxShape.circle,
          gradient: isWheel
              ? const SweepGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                )
              : null,
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.lightBorder,
            width: selected ? 3 : 1,
          ),
        ),
        child: isWheel
            ? const Icon(Icons.colorize, size: 15, color: AppColors.textPrimary)
            : (selected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.textPrimary,
                    )
                  : null),
      ),
    );
  }
}
