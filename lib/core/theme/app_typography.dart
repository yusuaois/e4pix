import 'package:flutter/material.dart';

/// 统一字号系统 — 所有 inline TextStyle 应迁移至此
class AppTypography {
  AppTypography._();

  // ── 标签（Section labels, button labels, metadata）──
  static const labelSmall = TextStyle(fontSize: 10, letterSpacing: 1.4);
  static const labelMedium = TextStyle(fontSize: 10.5);

  // ── 正文（Secondary labels, dialog text, slider values）──
  static const bodySmall = TextStyle(fontSize: 11);
  static const bodyMedium = TextStyle(fontSize: 11.5);
  static const bodyLarge = TextStyle(fontSize: 12);

  // ── 标题（Section headers, settings subtitles）──
  static const titleSmall = TextStyle(fontSize: 12.5);
  static const titleMedium = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );

  // ── 大标题（Dialog titles, screen headings）──
  static const headlineSmall = TextStyle(fontSize: 15);
  static const headlineMedium = TextStyle(fontSize: 16);
}
