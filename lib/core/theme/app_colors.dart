import 'package:flutter/material.dart';

/// 语义化颜色常量
class AppColors {
  AppColors._();

  // ── 文字透明度 ──
  static Color get disabledText => Colors.white.withValues(alpha: 0.4);
  static Color get faintText => Colors.white.withValues(alpha: 0.5);
  static Color get mediumText => Colors.white.withValues(alpha: 0.6);
  static Color get prominentText => Colors.white.withValues(alpha: 0.7);

  // ── 边框/分隔 ──
  static Color get subtleBorder => Colors.white.withValues(alpha: 0.05);
  static Color get faintBorder => Colors.white.withValues(alpha: 0.12);
  static Color get lightBorder => Colors.white.withValues(alpha: 0.15);

  // ── 背景 ──
  static const panelBg = Color(0xFF14141A);
  static const deepBg = Color(0xFF0E0E12);
  static const fallbackBg = Color(0xFF1A1A1A);
  static const surfaceBg = Color(0xFF101015);

  // ── 特殊 ──
  static Color get activeValue => Colors.greenAccent.withValues(alpha: 0.85);
}
