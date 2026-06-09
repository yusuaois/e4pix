import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/crop_params.dart';
import '../../core/models/watermark_config.dart';
import '../../native/raw_bridge.dart';
import '../../render/preview_renderer.dart';
import '../../services/watermark/watermark_asset_manager.dart';
import '../../state/providers.dart';
import 'multi_pass_preview.dart';

/// 水印边框预览组件
///
/// Layer 0: 背景（纯色 / 图片 / 模糊原图）
/// Layer 1: Logo + EXIF 信息
/// Layer 2: 清晰调色原图
class WatermarkPreview extends ConsumerWidget {
  final DecodedImageState state;
  final AdjustmentParams params;
  final LutState lut;
  final bool lutEnabled;

  const WatermarkPreview({
    super.key,
    required this.state,
    required this.params,
    required this.lut,
    required this.lutEnabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(watermarkConfigProvider);

    final hasLocals = params.locals.any(
      (l) => l.enabled && !l.params.isNeutral,
    );
    final hasSharpen = params.sharpenAmount > 0.001;
    final hasDenoise =
        params.denoiseLuma > 0.001 || params.denoiseColor > 0.001;
    final needFullPipeline = hasLocals || hasSharpen || hasDenoise;

    if (needFullPipeline) {
      final maskProgram = ref.watch(maskShaderProgramProvider).value;
      final develop = ref.watch(shaderProgramProvider).value;
      if (develop == null || maskProgram == null) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return _WatermarkLayout(
        config: config,
        buildImageLayer: (ctx, imageFitSize) {
          final isVertical = MediaQuery.of(ctx).size.shortestSide < 600;
          final previewQ = ref.watch(previewQualityProvider);
          final (idle, dragging) = previewQ.edges(isVertical: isVertical);
          return MultiPassPreview(
            developProgram: develop,
            maskProgram: maskProgram,
            sourceImage: state.uiImage,
            params: params,
            lutTexture: lutEnabled ? lut.textureA : null,
            lutSize: lutEnabled ? lut.sizeA : 0,
            lutTextureB: lutEnabled ? lut.textureB : null,
            lutSizeB: lutEnabled ? lut.sizeB : 0,
            curveTexture: ref.watch(effectiveCurveTextureProvider),
            sharpenProgram: ref.watch(sharpenShaderProgramProvider).value,
            denoiseProgram: ref.watch(denoiseShaderProgramProvider).value,
            idleMaxEdge: idle,
            draggingMaxEdge: dragging,
          );
        },
        buildBackgroundLayer:
            config.backgroundType == BackgroundType.blurredOriginal
            ? (ctx, bgSize) => _BlurredDevelopBackground(
                image: state.uiImage,
                params: params,
                lutTexture: lutEnabled ? lut.textureA : null,
                lutSize: lutEnabled ? lut.sizeA : 0,
                lutTextureB: lutEnabled ? lut.textureB : null,
                lutSizeB: lutEnabled ? lut.sizeB : 0,
                curveTexture: ref.watch(effectiveCurveTextureProvider),
                blurSigma: config.blurRadius,
                targetSize: bgSize,
              )
            : null,
        buildInfoLayer: (ctx, infoWidth, textColor) => _WatermarkInfoLayer(
          metadata: state.metadata,
          config: config,
          availableWidth: infoWidth,
          textColor: textColor,
        ),
        sourceImage: state.uiImage,
        crop: params.crop,
      );
    }

    final crop = params.crop;
    final image = state.uiImage;

    return _WatermarkLayout(
      config: config,
      buildImageLayer: (ctx, imageFitSize) {
        if (crop.isIdentity) {
          return PreviewRenderer(
            image: image,
            params: params,
            lutTexture: lutEnabled ? lut.textureA : null,
            lutSize: lutEnabled ? lut.sizeA : 0,
            lutTextureB: lutEnabled ? lut.textureB : null,
            lutSizeB: lutEnabled ? lut.sizeB : 0,
            curveTexture: ref.watch(effectiveCurveTextureProvider),
          );
        }
        // 有裁剪 → 构建带 transform 的渲染图
        final imgW = image.width.toDouble();
        final imgH = image.height.toDouble();
        final orientedW = crop.orientationSwapsAxes ? imgH : imgW;
        final orientedH = crop.orientationSwapsAxes ? imgW : imgH;
        final scale = imageFitSize.width / (orientedW * crop.width);
        final renderedFullW = imgW * scale;
        final renderedFullH = imgH * scale;
        final renderedOrientedW = orientedW * scale;
        final renderedOrientedH = orientedH * scale;

        final orientedImage = SizedBox(
          width: renderedOrientedW,
          height: renderedOrientedH,
          child: ClipRect(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(
                  crop.orientation * math.pi / 2 +
                      crop.straighten * math.pi / 180,
                )
                ..scaleByDouble(
                  crop.flipH ? -1.0 : 1.0,
                  crop.flipV ? -1.0 : 1.0,
                  1.0,
                  1.0,
                ),
              child: OverflowBox(
                minWidth: renderedFullW,
                maxWidth: renderedFullW,
                minHeight: renderedFullH,
                maxHeight: renderedFullH,
                child: SizedBox(
                  width: renderedFullW,
                  height: renderedFullH,
                  child: PreviewRenderer(
                    image: image,
                    params: params,
                    lutTexture: lutEnabled ? lut.textureA : null,
                    lutSize: lutEnabled ? lut.sizeA : 0,
                    lutTextureB: lutEnabled ? lut.textureB : null,
                    lutSizeB: lutEnabled ? lut.sizeB : 0,
                    curveTexture: ref.watch(effectiveCurveTextureProvider),
                  ),
                ),
              ),
            ),
          ),
        );

        return SizedBox.fromSize(
          size: imageFitSize,
          child: ClipRect(
            child: OverflowBox(
              minWidth: renderedOrientedW,
              maxWidth: renderedOrientedW,
              minHeight: renderedOrientedH,
              maxHeight: renderedOrientedH,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: Offset(
                  -crop.x * renderedOrientedW,
                  -crop.y * renderedOrientedH,
                ),
                child: orientedImage,
              ),
            ),
          ),
        );
      },
      buildBackgroundLayer:
          config.backgroundType == BackgroundType.blurredOriginal
          ? (ctx, bgSize) => _BlurredDevelopBackground(
              image: image,
              params: params,
              lutTexture: lutEnabled ? lut.textureA : null,
              lutSize: lutEnabled ? lut.sizeA : 0,
              lutTextureB: lutEnabled ? lut.textureB : null,
              lutSizeB: lutEnabled ? lut.sizeB : 0,
              curveTexture: ref.watch(effectiveCurveTextureProvider),
              blurSigma: config.blurRadius,
              targetSize: bgSize,
            )
          : null,
      buildInfoLayer: (ctx, infoWidth, textColor) => _WatermarkInfoLayer(
        metadata: state.metadata,
        config: config,
        availableWidth: infoWidth,
        textColor: textColor,
      ),
      sourceImage: image,
      crop: crop,
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 布局计算核心：确定三层各自的尺寸和位置
// ──────────────────────────────────────────────────────────────

typedef ImageLayerBuilder =
    Widget Function(BuildContext ctx, Size imageFitSize);
typedef BackgroundLayerBuilder =
    Widget? Function(BuildContext ctx, Size bgSize);
typedef InfoLayerBuilder =
    Widget Function(BuildContext ctx, double infoWidth, Color textColor);

class _WatermarkLayout extends ConsumerWidget {
  final WatermarkConfig config;
  final ImageLayerBuilder buildImageLayer;
  final BackgroundLayerBuilder? buildBackgroundLayer;
  final InfoLayerBuilder buildInfoLayer;
  final ui.Image sourceImage;
  final CropParams crop;

  const _WatermarkLayout({
    required this.config,
    required this.buildImageLayer,
    this.buildBackgroundLayer,
    required this.buildInfoLayer,
    required this.sourceImage,
    required this.crop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textColor = config.colorMode == WatermarkColorMode.light
        ? Colors.white
        : Colors.black;

    return Container(
      color: config.backgroundType == BackgroundType.solidColor
          ? Color(config.backgroundColor)
          : Colors.black,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final availW = constraints.maxWidth;
          final availH = constraints.maxHeight;

          // ── 计算原图区域 ──
          final borderW = config.borderWidth;
          final imgW = sourceImage.width.toDouble();
          final imgH = sourceImage.height.toDouble();
          final outAspect = crop.outAspectFor(imgW, imgH);

          // 可用空间扣掉边框
          final innerMaxW = (availW - 2 * borderW).clamp(1.0, availW);
          final innerMaxH = (availH - 2 * borderW).clamp(1.0, availH);

          final imageFit = applyBoxFit(
            BoxFit.contain,
            Size(outAspect, 1.0),
            Size(innerMaxW, innerMaxH),
          );
          final imageBaseSize = imageFit.destination;
          final scale = config.imageScale.clamp(0.01, 1.0);
          final imageDisplayW = imageBaseSize.width * scale;
          final imageDisplayH = imageBaseSize.height * scale;

          // ── 信息层区域 ──
          final infoAvailH = availH - imageDisplayH - 2 * borderW;
          final infoAbove = config.infoPlacement == InfoPlacement.above;

          // ── 构建各层 ──
          final imageLayer = RepaintBoundary(
            child: buildImageLayer(ctx, Size(imageDisplayW, imageDisplayH)),
          );

          // Layer 0
          Widget? bgLayer;
          final bgBuilder = buildBackgroundLayer;
          if (config.backgroundType == BackgroundType.solidColor) {
            bgLayer = null; // handled by Container color
          } else if (config.backgroundType == BackgroundType.blurredOriginal &&
              bgBuilder != null) {
            bgLayer = Positioned.fill(
              child: RepaintBoundary(
                child: bgBuilder(ctx, Size(availW, availH)),
              ),
            );
          } else if (config.backgroundType == BackgroundType.image &&
              config.customBackgroundPath != null) {
            bgLayer = Positioned.fill(
              child: RepaintBoundary(
                child: _CustomImageBackground(
                  filename: config.customBackgroundPath!,
                ),
              ),
            );
          }

          // Layer 1
          final infoLayer = infoAvailH > 20
              ? Positioned(
                  left: borderW,
                  right: borderW,
                  top: infoAbove ? 0 : null,
                  bottom: infoAbove ? null : 0,
                  height: infoAvailH.clamp(0, availH),
                  child: RepaintBoundary(
                    child: buildInfoLayer(ctx, availW - 2 * borderW, textColor),
                  ),
                )
              : const SizedBox.shrink();

          // Layer 2 — 带圆角 + 阴影的原图层
          final shadowColor = Colors.black.withValues(
            alpha: config.shadowIntensity * 0.6,
          );
          final shadowBlur = config.shadowIntensity * 30.0;
          final shadowOffset = config.shadowIntensity * 8.0;

          final imageLayerDecorated = Center(
            child: Container(
              width: imageDisplayW,
              height: imageDisplayH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(config.cornerRadius),
                boxShadow: config.shadowIntensity > 0.001
                    ? [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: shadowBlur,
                          offset: Offset(0, shadowOffset),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(config.cornerRadius),
                child: imageLayer,
              ),
            ),
          );

          return Stack(
            children: [
              ?bgLayer,
              if (infoAbove) infoLayer,
              imageLayerDecorated,
              if (!infoAbove) infoLayer,
            ],
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 0: 低分辨率 Develop 渲染 + 高斯模糊
// ──────────────────────────────────────────────────────────────

class _BlurredDevelopBackground extends ConsumerWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;
  final double blurSigma;
  final Size targetSize;

  const _BlurredDevelopBackground({
    required this.image,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    required this.blurSigma,
    required this.targetSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDragging = ref.watch(isUserDraggingSliderProvider);
    final programAsync = ref.watch(shaderProgramProvider);

    return programAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (program) {
        // 降采样：拖动时 64px，静止时 256px
        final maxEdge = isDragging ? 64.0 : 256.0;
        final imgW = image.width.toDouble();
        final imgH = image.height.toDouble();
        final longest = math.max(imgW, imgH);
        final downscale = longest > maxEdge ? maxEdge / longest : 1.0;
        final thumbW = (imgW * downscale).round();
        final thumbH = (imgH * downscale).round();

        // 缩略图放大的比例
        final fillScale = math.max(
          targetSize.width / thumbW,
          targetSize.height / thumbH,
        );

        // 调整模糊量以补偿降采样
        final compensatedBlur = blurSigma * downscale * fillScale;

        return ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: compensatedBlur.clamp(0.0, 50.0),
              sigmaY: compensatedBlur.clamp(0.0, 50.0),
            ),
            child: SizedBox(
              width: thumbW.toDouble(),
              height: thumbH.toDouble(),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: imgW,
                  height: imgH,
                  child: PreviewRenderer(
                    image: image,
                    params: params,
                    lutTexture: lutTexture,
                    lutSize: lutSize,
                    lutTextureB: lutTextureB,
                    lutSizeB: lutSizeB,
                    curveTexture: curveTexture,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 0b: 自定义图片背景
// ──────────────────────────────────────────────────────────────

class _CustomImageBackground extends StatefulWidget {
  final String filename;
  const _CustomImageBackground({required this.filename});

  @override
  State<_CustomImageBackground> createState() => _CustomImageBackgroundState();
}

class _CustomImageBackgroundState extends State<_CustomImageBackground> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CustomImageBackground old) {
    super.didUpdateWidget(old);
    if (old.filename != widget.filename) {
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await WatermarkAssetManager.readImageBytes(widget.filename);
      if (bytes != null && mounted) {
        final codec = await ui.instantiateImageCodec(bytes);
        final img = (await codec.getNextFrame()).image;
        if (mounted) setState(() => _image = img);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return Container(color: const Color(0xFF1A1A1A));
    }
    return RawImage(image: _image, fit: BoxFit.cover);
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 1: Logo + EXIF 信息层
// ──────────────────────────────────────────────────────────────

class _WatermarkInfoLayer extends StatelessWidget {
  final RawMetadata? metadata;
  final WatermarkConfig config;
  final double availableWidth;
  final Color textColor;

  const _WatermarkInfoLayer({
    required this.metadata,
    required this.config,
    required this.availableWidth,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo =
        config.logoSource == LogoSource.builtin && config.logoBrand != null ||
        config.logoSource == LogoSource.custom && config.customLogoPath != null;

    if (!config.showExif && !hasLogo) {
      return const SizedBox.shrink();
    }

    final exifStr = config.showExif ? _buildExifString(config, metadata) : null;
    if (exifStr == null && !hasLogo) {
      return const SizedBox.shrink();
    }

    // Logo 资源：内置品牌 / 自定义文件
    final String? logoAsset;
    final String? logoFilePath;
    if (config.logoSource == LogoSource.custom &&
        config.customLogoPath != null) {
      logoAsset = null;
      logoFilePath = config.customLogoPath!;
    } else if (config.logoSource == LogoSource.builtin &&
        config.logoBrand != null) {
      logoAsset = _logoAssetPath(config.logoBrand!, config.colorMode);
      logoFilePath = null;
    } else {
      logoAsset = null;
      logoFilePath = null;
    }

    final fontWeight = _indexToFontWeight(config.fontWeightIndex);
    final textStyle = TextStyle(
      fontSize: config.fontSize,
      fontWeight: fontWeight,
      color: textColor.withValues(alpha: config.textOpacity),
      fontFamily: config.fontFamily,
    );

    return Padding(
      padding: EdgeInsets.all(config.textPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (logoAsset != null || logoFilePath != null)
            Opacity(
              opacity: config.logoOpacity,
              child: _LogoImage(
                assetPath: logoAsset,
                filePath: logoFilePath,
                maxHeight: config.logoSize * 48,
              ),
            ),
          if ((logoAsset != null || logoFilePath != null) && exifStr != null)
            SizedBox(height: config.textPadding / 2),
          if (exifStr != null)
            Text(
              exifStr,
              style: textStyle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  static String? _logoAssetPath(String? brand, WatermarkColorMode mode) {
    if (brand == null) return null;
    final dir = mode == WatermarkColorMode.light ? 'light' : 'dark';
    return 'assets/borders/logos/$dir/$brand.webp';
  }

  static String? _buildExifString(WatermarkConfig config, RawMetadata? m) {
    if (config.exifMode == ExifMode.custom) {
      final t = config.customExifText?.trim();
      return (t != null && t.isNotEmpty) ? t : null;
    }
    if (m == null) return null;
    final parts = <String>[];
    // 相机型号 + 镜头
    final cam = m.cameraModel.trim();
    if (cam.isNotEmpty) parts.add(cam);
    // ISO
    if (m.iso > 0) parts.add('ISO ${m.iso}');
    // 光圈
    if (m.aperture > 0) parts.add('f/${m.aperture.toStringAsFixed(1)}');
    // 快门
    if (m.shutter > 0) parts.add(m.shutterDisplay);
    // 焦距
    if (m.focalLength > 0) parts.add('${m.focalLength.toStringAsFixed(0)}mm');
    // 镜头型号（仅在和相机不同时显示）
    final lens = m.lensModel.trim();
    if (lens.isNotEmpty && lens != cam) parts.add(lens);

    if (parts.isEmpty) return null;
    return parts.join(' | ');
  }

  static FontWeight _indexToFontWeight(int idx) {
    const map = [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ];
    return map[idx.clamp(0, map.length - 1)];
  }
}

// ──────────────────────────────────────────────────────────────
// Logo 图片加载组件（带透明度）
// ──────────────────────────────────────────────────────────────

class _LogoImage extends StatefulWidget {
  final String? assetPath;
  final String? filePath;
  final double maxHeight;

  const _LogoImage({this.assetPath, this.filePath, required this.maxHeight});

  @override
  State<_LogoImage> createState() => _LogoImageState();
}

class _LogoImageState extends State<_LogoImage> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LogoImage old) {
    super.didUpdateWidget(old);
    if (old.assetPath != widget.assetPath || old.filePath != widget.filePath) {
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      ui.Image? img;
      if (widget.filePath != null) {
        final bytes = await WatermarkAssetManager.readImageBytes(
          widget.filePath!,
        );
        if (bytes != null) {
          final codec = await ui.instantiateImageCodec(bytes);
          img = (await codec.getNextFrame()).image;
        }
      } else if (widget.assetPath != null) {
        img = await _decodeAssetImage(widget.assetPath!);
      }
      if (mounted && img != null) setState(() => _image = img);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) return const SizedBox.shrink();
    return RawImage(
      image: _image,
      height: widget.maxHeight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// 从 asset 解码为 ui.Image
Future<ui.Image> _decodeAssetImage(String assetPath) async {
  final bundle = rootBundle;
  final data = await bundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}
