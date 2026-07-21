import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// 从种子色构建完整的暗色 [ThemeData]
///
/// 灰阶种子（白/灰/黑）走 [_grayScheme] 中性路径，避免
/// [ColorScheme.fromSeed] 注入默认蓝色调
ThemeData appTheme(ColorScheme scheme) => ThemeData(
  useMaterial3: true,
  colorScheme: scheme,
  scaffoldBackgroundColor: AppColors.scaffoldBg,
  dialogTheme: const DialogThemeData(backgroundColor: AppColors.elevatedBg),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.elevatedBg,
    contentTextStyle: AppTypography.bodyLarge.copyWith(
      color: AppColors.textPrimary,
    ),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  hoverColor: Colors.white.withValues(alpha: 0.08),
  splashColor: Colors.white.withValues(alpha: 0.06),
  highlightColor: Colors.white.withValues(alpha: 0.04),
  focusColor: Colors.white.withValues(alpha: 0.12),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  ),
  sliderTheme: SliderThemeData(
    trackHeight: 2.0,
    inactiveTrackColor: AppColors.inactiveTrack,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayColor: AppColors.subtleBorder,
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
  ),
);

/// 从种子色构建暗色 [ColorScheme]
ColorScheme customColorScheme(int seed) {
  final r = (seed >> 16) & 0xFF;
  final g = (seed >> 8) & 0xFF;
  final b = seed & 0xFF;
  final isGray = (r - g).abs() <= 2 && (g - b).abs() <= 2 && (r - b).abs() <= 2;
  if (isGray) return _grayScheme(seed);

  return ColorScheme.fromSeed(
    seedColor: Color(seed),
    brightness: Brightness.dark,
  ).copyWith(surface: AppColors.panelBg, onSurface: AppColors.textPrimary);
}

/// 从灰度 seed 构建纯中性 ColorScheme
///
/// 种子色的 luma 会被重映射到 [140, 255] 区间，保证在暗色 panelBg
/// (`#1E1E1E`) 上始终有足够的亮度对比度
ColorScheme _grayScheme(int seed) {
  final r = (seed >> 16) & 0xFF;
  final g = (seed >> 8) & 0xFF;
  final b = seed & 0xFF;
  final v = (r * 0.299 + g * 0.587 + b * 0.114).round();
  final mv = 140 + (v * 115 / 255).round();
  final primary = Color.fromARGB(255, mv, mv, mv);
  final cv = (mv * 0.30).round();
  final container = Color.fromARGB(255, cv, cv, cv);

  return ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: primary,
    onPrimary: AppColors.scaffoldBg,
    primaryContainer: container,
    onPrimaryContainer: primary,
    secondary: primary,
    onSecondary: AppColors.scaffoldBg,
    secondaryContainer: container,
    onSecondaryContainer: primary,
    tertiary: primary,
    onTertiary: AppColors.scaffoldBg,
    tertiaryContainer: container,
    onTertiaryContainer: primary,
    surface: AppColors.panelBg,
    onSurface: AppColors.textPrimary,
  );
}
