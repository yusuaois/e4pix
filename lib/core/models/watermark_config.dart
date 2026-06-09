import 'package:flutter/foundation.dart';

/// 背景类型
enum BackgroundType {
  /// 纯色背景
  solidColor,

  /// 自定义图片（从 e4pix/custom_watermarks/ 加载）
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

/// EXIF 来源模式
enum ExifMode {
  /// 自动从 RawMetadata 提取
  auto,

  /// 用户自定义文本
  custom,
}

/// Logo 来源
enum LogoSource {
  /// 内置品牌 Logo（assets/borders/logos/）
  builtin,

  /// 用户导入的自定义 Logo
  custom,
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
  final double blurRadius; // 0–100 px
  final double borderWidth; // 20–200 px
  final double imageScale; // 0.0–1.0

  // ── 质感 ──
  final double cornerRadius; // 0–100 px
  final double shadowIntensity; // 0.0–1.0

  // ── 背景 ──
  final BackgroundType backgroundType;
  final int backgroundColor; // 32-bit ARGB
  /// 自定义背景图文件名（位于 e4pix/custom_watermarks/ 下）
  final String? customBackgroundPath;

  // ── Logo ──
  final LogoSource logoSource;

  /// 内置品牌名（logoSource == builtin 时生效）
  final String? logoBrand;

  /// 自定义 Logo 文件名（logoSource == custom 时生效，位于 custom_watermarks/ 下）
  final String? customLogoPath;
  final double logoSize; // 0.0–1.0 相对大小
  final double logoOpacity; // 0.0–1.0

  // ── 文本与 EXIF ──
  final bool showExif;
  final ExifMode exifMode;

  /// 自定义 EXIF 文本（exifMode == custom 时生效）
  final String? customExifText;
  final String? fontFamily;
  final double fontSize; // pt
  final int fontWeightIndex; // 0=w400 … 4=w800
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
    this.customBackgroundPath,
    this.logoSource = LogoSource.builtin,
    this.logoBrand,
    this.customLogoPath,
    this.logoSize = 0.5,
    this.logoOpacity = 0.9,
    this.showExif = true,
    this.exifMode = ExifMode.auto,
    this.customExifText,
    this.fontFamily,
    this.fontSize = 13.0,
    this.fontWeightIndex = 2, // w600
    this.textOpacity = 0.9,
    this.textPadding = 12.0,
    this.colorMode = WatermarkColorMode.light,
    this.infoPlacement = InfoPlacement.below,
  });

  static const defaults = WatermarkConfig();

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
    String? customBackgroundPath,
    bool clearCustomBg = false,
    LogoSource? logoSource,
    String? logoBrand,
    bool clearLogoBrand = false,
    String? customLogoPath,
    bool clearCustomLogo = false,
    double? logoSize,
    double? logoOpacity,
    bool? showExif,
    ExifMode? exifMode,
    String? customExifText,
    bool clearCustomExif = false,
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
    customBackgroundPath: clearCustomBg
        ? null
        : (customBackgroundPath ?? this.customBackgroundPath),
    logoSource: logoSource ?? this.logoSource,
    logoBrand: clearLogoBrand ? null : (logoBrand ?? this.logoBrand),
    customLogoPath: clearCustomLogo
        ? null
        : (customLogoPath ?? this.customLogoPath),
    logoSize: logoSize ?? this.logoSize,
    logoOpacity: logoOpacity ?? this.logoOpacity,
    showExif: showExif ?? this.showExif,
    exifMode: exifMode ?? this.exifMode,
    customExifText: clearCustomExif
        ? null
        : (customExifText ?? this.customExifText),
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
          customBackgroundPath == other.customBackgroundPath &&
          logoSource == other.logoSource &&
          logoBrand == other.logoBrand &&
          customLogoPath == other.customLogoPath &&
          logoSize == other.logoSize &&
          logoOpacity == other.logoOpacity &&
          showExif == other.showExif &&
          exifMode == other.exifMode &&
          customExifText == other.customExifText &&
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
    customBackgroundPath,
    logoSource,
    logoBrand,
    customLogoPath,
    logoSize,
    logoOpacity,
    showExif,
    exifMode,
    customExifText,
    fontFamily,
    fontSize,
    fontWeightIndex,
    textOpacity,
    textPadding,
    colorMode,
    infoPlacement,
  ]);
}
