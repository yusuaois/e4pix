import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_colors.dart';

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

/// 信息层位置
enum InfoPlacement {
  /// Logo + EXIF 在原图层上方
  above,

  /// Logo + EXIF 在原图层下方
  below,

  /// 叠加在原图左上角
  overlayTopLeft,

  /// 叠加在原图右上角
  overlayTopRight,

  /// 叠加在原图左下角
  overlayBottomLeft,

  /// 叠加在原图右下角
  overlayBottomRight,
}

/// [InfoPlacement] 辅助扩展
extension InfoPlacementExt on InfoPlacement {
  /// 信息层是否在 Z 轴位于原图之后（即原图覆盖在信息层上方）
  bool get behindImage => this == InfoPlacement.above;

  /// 是否为叠加模式（信息层覆盖在原图之上）
  bool get isOverlay => switch (this) {
    InfoPlacement.overlayTopLeft ||
    InfoPlacement.overlayTopRight ||
    InfoPlacement.overlayBottomLeft ||
    InfoPlacement.overlayBottomRight => true,
    _ => false,
  };

  /// UI 显示标签
  String get displayLabel => switch (this) {
    InfoPlacement.above => 'Above Image',
    InfoPlacement.below => 'Below Image',
    InfoPlacement.overlayTopLeft => '↖ Top Left',
    InfoPlacement.overlayTopRight => '↗ Top Right',
    InfoPlacement.overlayBottomLeft => '↙ Bottom Left',
    InfoPlacement.overlayBottomRight => '↘ Bottom Right',
  };
}

/// EXIF 来源模式
enum ExifMode {
  /// 自动从 RawMetadata 提取
  auto,

  /// 用户自定义文本
  custom,
}

/// 可选 EXIF 字段（勾选决定哪些字段出现在水印文字中）
enum ExifField {
  /// 相机型号
  cameraModel,

  /// 镜头型号
  lensModel,

  /// ISO
  iso,

  /// 光圈
  aperture,

  /// 快门速度
  shutter,

  /// 焦距
  focalLength,
}

/// [ExifField] 显示标签
extension ExifFieldExt on ExifField {
  String get displayLabel => switch (this) {
    ExifField.cameraModel => 'Camera',
    ExifField.lensModel => 'Lens',
    ExifField.iso => 'ISO',
    ExifField.aperture => 'Aperture',
    ExifField.shutter => 'Shutter',
    ExifField.focalLength => 'Focal Length',
  };
}

/// Logo 来源
enum LogoSource {
  /// 内置品牌 Logo（assets/borders/logos/）
  builtin,

  /// 用户导入的自定义 Logo
  custom,
}

/// 画布宽高比
enum CanvasAspectRatio {
  /// 自动（跟随原图比例）
  auto,

  /// 1:1 正方形
  square,

  /// 4:3
  ratio4_3,

  /// 3:2
  ratio3_2,

  /// 16:9
  ratio16_9,

  /// 3:4（竖版）
  ratio3_4,

  /// 2:3（竖版）
  ratio2_3,

  /// 9:16（竖版）
  ratio9_16,
}

/// [CanvasAspectRatio] 对应的数值 w/h，auto 返回 null
extension CanvasAspectRatioExt on CanvasAspectRatio {
  double? get value => switch (this) {
    CanvasAspectRatio.auto => null,
    CanvasAspectRatio.square => 1.0,
    CanvasAspectRatio.ratio4_3 => 4.0 / 3.0,
    CanvasAspectRatio.ratio3_2 => 3.0 / 2.0,
    CanvasAspectRatio.ratio16_9 => 16.0 / 9.0,
    CanvasAspectRatio.ratio3_4 => 3.0 / 4.0,
    CanvasAspectRatio.ratio2_3 => 2.0 / 3.0,
    CanvasAspectRatio.ratio9_16 => 9.0 / 16.0,
  };

  /// 显示标签
  String get displayLabel => switch (this) {
    CanvasAspectRatio.auto => tr("auto"),
    CanvasAspectRatio.square => '1:1',
    CanvasAspectRatio.ratio4_3 => '4:3',
    CanvasAspectRatio.ratio3_2 => '3:2',
    CanvasAspectRatio.ratio16_9 => '16:9',
    CanvasAspectRatio.ratio3_4 => '3:4',
    CanvasAspectRatio.ratio2_3 => '2:3',
    CanvasAspectRatio.ratio9_16 => '9:16',
  };
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
  final Color backgroundColor;

  /// 自定义背景图文件名（位于 e4pix/custom_watermarks/ 下）
  final String? customBackgroundPath;

  /// 画布宽高比（null / auto = 跟随原图）
  final CanvasAspectRatio canvasAspectRatio;

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

  /// 选中的 EXIF 字段（空集 = 显示全部）
  final Set<ExifField> enabledExifFields;

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
    this.backgroundColor = AppColors.fallbackBg,
    this.customBackgroundPath,
    this.canvasAspectRatio = CanvasAspectRatio.auto,
    this.logoSource = LogoSource.builtin,
    this.logoBrand,
    this.customLogoPath,
    this.logoSize = 0.5,
    this.logoOpacity = 0.9,
    this.showExif = true,
    this.exifMode = ExifMode.auto,
    this.enabledExifFields = const {},
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
    Color? backgroundColor,
    String? customBackgroundPath,
    bool clearCustomBg = false,
    CanvasAspectRatio? canvasAspectRatio,
    LogoSource? logoSource,
    String? logoBrand,
    bool clearLogoBrand = false,
    String? customLogoPath,
    bool clearCustomLogo = false,
    double? logoSize,
    double? logoOpacity,
    bool? showExif,
    ExifMode? exifMode,
    Set<ExifField>? enabledExifFields,
    bool clearExifFields = false,
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
    canvasAspectRatio: canvasAspectRatio ?? this.canvasAspectRatio,
    logoSource: logoSource ?? this.logoSource,
    logoBrand: clearLogoBrand ? null : (logoBrand ?? this.logoBrand),
    customLogoPath: clearCustomLogo
        ? null
        : (customLogoPath ?? this.customLogoPath),
    logoSize: logoSize ?? this.logoSize,
    logoOpacity: logoOpacity ?? this.logoOpacity,
    showExif: showExif ?? this.showExif,
    exifMode: exifMode ?? this.exifMode,
    enabledExifFields: clearExifFields
        ? {}
        : (enabledExifFields ?? this.enabledExifFields),
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
          canvasAspectRatio == other.canvasAspectRatio &&
          logoSource == other.logoSource &&
          logoBrand == other.logoBrand &&
          customLogoPath == other.customLogoPath &&
          logoSize == other.logoSize &&
          logoOpacity == other.logoOpacity &&
          showExif == other.showExif &&
          exifMode == other.exifMode &&
          setEquals(enabledExifFields, other.enabledExifFields) &&
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
    canvasAspectRatio,
    logoSource,
    logoBrand,
    customLogoPath,
    logoSize,
    logoOpacity,
    showExif,
    exifMode,
    Object.hashAll(enabledExifFields),
    customExifText,
    fontFamily,
    fontSize,
    fontWeightIndex,
    textOpacity,
    textPadding,
    colorMode,
    infoPlacement,
  ]);

  // ──────────────────────────────────────────────────────────
  // JSON 序列化
  // ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'version': 1,
    'blurRadius': blurRadius,
    'borderWidth': borderWidth,
    'imageScale': imageScale,
    'cornerRadius': cornerRadius,
    'shadowIntensity': shadowIntensity,
    'backgroundType': backgroundType.name,
    'backgroundColor': backgroundColor.toARGB32(),
    'customBackgroundPath': customBackgroundPath,
    'canvasAspectRatio': canvasAspectRatio.name,
    'logoSource': logoSource.name,
    'logoBrand': logoBrand,
    'customLogoPath': customLogoPath,
    'logoSize': logoSize,
    'logoOpacity': logoOpacity,
    'showExif': showExif,
    'exifMode': exifMode.name,
    'enabledExifFields': enabledExifFields.map((f) => f.name).toList(),
    'customExifText': customExifText,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fontWeightIndex': fontWeightIndex,
    'textOpacity': textOpacity,
    'textPadding': textPadding,
    'colorMode': colorMode.name,
    'infoPlacement': infoPlacement.name,
  };

  factory WatermarkConfig.fromJson(Map<String, dynamic> json) {
    final exifFields =
        (json['enabledExifFields'] as List<dynamic>?)
            ?.map((e) => ExifField.values.byName(e as String))
            .toSet() ??
        const {};
    return WatermarkConfig(
      enabled: false, // 始终初始化为关闭
      blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 30.0,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 80.0,
      imageScale: (json['imageScale'] as num?)?.toDouble() ?? 0.85,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 12.0,
      shadowIntensity: (json['shadowIntensity'] as num?)?.toDouble() ?? 0.35,
      backgroundType: BackgroundType.values.byName(
        json['backgroundType'] as String? ?? 'blurredOriginal',
      ),
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : AppColors.fallbackBg,
      customBackgroundPath: json['customBackgroundPath'] as String?,
      canvasAspectRatio: CanvasAspectRatio.values.byName(
        json['canvasAspectRatio'] as String? ?? 'auto',
      ),
      logoSource: LogoSource.values.byName(
        json['logoSource'] as String? ?? 'builtin',
      ),
      logoBrand: json['logoBrand'] as String?,
      customLogoPath: json['customLogoPath'] as String?,
      logoSize: (json['logoSize'] as num?)?.toDouble() ?? 0.5,
      logoOpacity: (json['logoOpacity'] as num?)?.toDouble() ?? 0.9,
      showExif: json['showExif'] as bool? ?? true,
      exifMode: ExifMode.values.byName(json['exifMode'] as String? ?? 'auto'),
      enabledExifFields: exifFields,
      customExifText: json['customExifText'] as String?,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13.0,
      fontWeightIndex: json['fontWeightIndex'] as int? ?? 2,
      textOpacity: (json['textOpacity'] as num?)?.toDouble() ?? 0.9,
      textPadding: (json['textPadding'] as num?)?.toDouble() ?? 12.0,
      colorMode: WatermarkColorMode.values.byName(
        json['colorMode'] as String? ?? 'light',
      ),
      infoPlacement: InfoPlacement.values.byName(
        json['infoPlacement'] as String? ?? 'below',
      ),
    );
  }
}
