import 'package:flutter/foundation.dart';

/// 背景类型
enum BackgroundType {
  /// 纯色背景
  solidColor,

  /// 自定义图片
  image,

  /// 使用当前调色原图 + 高斯模糊
  blurredOriginal,
}

/// Light/Dark 模式（控制文字黑白 + 联动对应 Logo 目录）
enum WatermarkColorMode { light, dark }

/// 信息层位置（相对原图层）
enum InfoPlacement {
  /// Logo + EXIF 在原图层上方
  above,

  /// Logo + EXIF 在原图层下方
  below,
}

/// 已支持的品牌 Logo 列表
const kAvailableLogoBrands = [
  'canon',
  'caye',
  'dji',
  'fujifilm',
  'hasselblad',
  'leica',
  'nikon',
  'olympus',
  'panasonic',
  'pentax',
  'ricoh',
  'sony',
  'zeiss',
];

/// 水印边框完整配置
@immutable
class WatermarkConfig {
  // ── 总开关 ──
  final bool enabled;

  // ── 布局 ──
  /// 背景模糊半径 (0–100 px)
  final double blurRadius;

  /// 边框宽度 (20–200 px)
  final double borderWidth;

  /// 原图缩放比例 (0.0–1.0)，1.0 = 原图撑满可用空间
  final double imageScale;

  // ── 质感 ──
  /// 原图层圆角大小 (0–100 px)
  final double cornerRadius;

  /// 立体阴影强度 (0.0–1.0)，作用于原图下方
  final double shadowIntensity;

  // ── 背景 ──
  final BackgroundType backgroundType;
  final int backgroundColor; // 32-bit ARGB

  // ── Logo ──
  /// null = 不显示 Logo
  final String? logoBrand;
  final double logoSize; // 0.0–1.0 相对大小
  final double logoOpacity; // 0.0–1.0

  // ── 文本与 EXIF ──
  final bool showExif;
  final String? fontFamily; // null = 系统默认
  final double fontSize; // pt
  final int fontWeightIndex; // 0=w400, 1=w500, 2=w600, 3=w700, 4=w800
  final double textOpacity; // 0.0–1.0
  final double textPadding; // 内容边距 px
  final WatermarkColorMode colorMode;
  final InfoPlacement infoPlacement;

  const WatermarkConfig({
    this.enabled = false,
    this.blurRadius = 30.0,
    this.borderWidth = 80.0,
    this.imageScale = 0.85,
    this.cornerRadius = 12.0,
    this.shadowIntensity = 0.35,
    this.backgroundType = BackgroundType.blurredOriginal,
    this.backgroundColor = 0xFF1A1A1A,
    this.logoBrand,
    this.logoSize = 0.5,
    this.logoOpacity = 0.9,
    this.showExif = true,
    this.fontFamily,
    this.fontSize = 13.0,
    this.fontWeightIndex = 2, // w600
    this.textOpacity = 0.9,
    this.textPadding = 12.0,
    this.colorMode = WatermarkColorMode.light,
    this.infoPlacement = InfoPlacement.below,
  });

  /// 一键开启时合理的默认外观
  static const defaults = WatermarkConfig();

  /// 开/关切换便捷方法
  WatermarkConfig get toggled => copyWith(enabled: !enabled);

  WatermarkConfig copyWith({
    bool? enabled,
    double? blurRadius,
    double? borderWidth,
    double? imageScale,
    double? cornerRadius,
    double? shadowIntensity,
    BackgroundType? backgroundType,
    int? backgroundColor,
    String? logoBrand,
    bool clearLogo = false,
    double? logoSize,
    double? logoOpacity,
    bool? showExif,
    String? fontFamily,
    bool clearFontFamily = false,
    double? fontSize,
    int? fontWeightIndex,
    double? textOpacity,
    double? textPadding,
    WatermarkColorMode? colorMode,
    InfoPlacement? infoPlacement,
  }) => WatermarkConfig(
    enabled: enabled ?? this.enabled,
    blurRadius: blurRadius ?? this.blurRadius,
    borderWidth: borderWidth ?? this.borderWidth,
    imageScale: imageScale ?? this.imageScale,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    shadowIntensity: shadowIntensity ?? this.shadowIntensity,
    backgroundType: backgroundType ?? this.backgroundType,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    logoBrand: clearLogo ? null : (logoBrand ?? this.logoBrand),
    logoSize: logoSize ?? this.logoSize,
    logoOpacity: logoOpacity ?? this.logoOpacity,
    showExif: showExif ?? this.showExif,
    fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
    fontSize: fontSize ?? this.fontSize,
    fontWeightIndex: fontWeightIndex ?? this.fontWeightIndex,
    textOpacity: textOpacity ?? this.textOpacity,
    textPadding: textPadding ?? this.textPadding,
    colorMode: colorMode ?? this.colorMode,
    infoPlacement: infoPlacement ?? this.infoPlacement,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatermarkConfig &&
          enabled == other.enabled &&
          blurRadius == other.blurRadius &&
          borderWidth == other.borderWidth &&
          imageScale == other.imageScale &&
          cornerRadius == other.cornerRadius &&
          shadowIntensity == other.shadowIntensity &&
          backgroundType == other.backgroundType &&
          backgroundColor == other.backgroundColor &&
          logoBrand == other.logoBrand &&
          logoSize == other.logoSize &&
          logoOpacity == other.logoOpacity &&
          showExif == other.showExif &&
          fontFamily == other.fontFamily &&
          fontSize == other.fontSize &&
          fontWeightIndex == other.fontWeightIndex &&
          textOpacity == other.textOpacity &&
          textPadding == other.textPadding &&
          colorMode == other.colorMode &&
          infoPlacement == other.infoPlacement;

  @override
  int get hashCode => Object.hashAll([
    enabled,
    blurRadius,
    borderWidth,
    imageScale,
    cornerRadius,
    shadowIntensity,
    backgroundType,
    backgroundColor,
    logoBrand,
    logoSize,
    logoOpacity,
    showExif,
    fontFamily,
    fontSize,
    fontWeightIndex,
    textOpacity,
    textPadding,
    colorMode,
    infoPlacement,
  ]);
}
