import 'package:flutter/material.dart';

/// 语义化颜色常量 — 中性深色主题
class AppColors {
  AppColors._();

  // ── 背景（中性黑/灰梯度）──
  static const scaffoldBg = Color(0xFF121212); // 主屏背景：极深炭黑
  static const panelBg = Color(0xFF1E1E1E); // 卡片/面板背景：中性深灰
  static const surfaceBg = Color(0xFF242424); // 悬浮元素背景：稍浅灰
  static const elevatedBg = Color(0xFF2A2A2A); // 高层级背景（对话框等）
  static const fallbackBg = Color(0xFF1A1A1A);

  // ── 文字（三梯度亮度）──
  static const textPrimary = Color(0xFFFFFFFF); // 主标题 / 激活态
  static const textSecondary = Color(0xFFE0E0E0); // 次要文字 / 副标题
  static const textTertiary = Color(0xFF888888); // 占位 / 禁用态
  // 旧 API 兼容（基于白色的透明度）
  static Color get disabledText => Colors.white.withValues(alpha: 0.38);
  static Color get faintText => Colors.white.withValues(alpha: 0.50);
  static Color get mediumText => Colors.white.withValues(alpha: 0.60);
  static Color get prominentText => Colors.white.withValues(alpha: 0.87);

  // ── 激活/高亮（中性白灰，无彩色）──
  static const active = Color(0xFFFFFFFF);
  static Color get activeBg => Colors.white.withValues(alpha: 0.10);
  static Color get activeValue => Colors.white.withValues(alpha: 0.95);

  // ── 滑块专用 ──
  static const inactiveTrack = Color(0xFF444444);

  // ── 边框/分割线 ──
  static Color get subtleBorder => Colors.white.withValues(alpha: 0.05);
  static Color get faintBorder => Colors.white.withValues(alpha: 0.12);
  static Color get lightBorder => Colors.white.withValues(alpha: 0.15);
  static Color get dividerLine => Colors.white.withValues(alpha: 0.08);

  // ── 语义色（降饱和 — 仅不可替代的语义场景使用）──
  static const semanticSuccess = Color(0xFF66BB6A);
  static const semanticWarning = Color(0xFFFFCA28);
  static const semanticError = Color(0xFFEF5350);

  // ── 可视化通道色（直方图 / 曲线 / HSL 色相带）──
  // 直方图 RGB
  static const histRed = Color(0xFFFF6464);
  static const histGreen = Color(0xFF60E060);
  static const histBlue = Color(0xFF6088FF);
  // 曲线 RGB + Luminance
  static const curveRed = Color(0xFFE5534B);
  static const curveGreen = Color(0xFF4CAF50);
  static const curveBlue = Color(0xFF5B8DEF);
  static const curveLum = Color(0xFFCCCCCC);
  // HSL 8 色相带
  static const hslBand0 = Color(0xFFE53935);
  static const hslBand1 = Color(0xFFFB8C00);
  static const hslBand2 = Color(0xFFFDD835);
  static const hslBand3 = Color(0xFF43A047);
  static const hslBand4 = Color(0xFF00ACC1);
  static const hslBand5 = Color(0xFF1E88E5);
  static const hslBand6 = Color(0xFF8E24AA);
  static const hslBand7 = Color(0xFFD81B60);
}
