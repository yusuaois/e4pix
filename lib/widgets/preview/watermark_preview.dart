import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/crop_params.dart';
import '../../core/models/watermark_config.dart';
import '../../native/raw_bridge.dart';
import '../../utils/image_loader_util.dart';
import '../../render/preview_renderer.dart';
import '../../render/watermark_geometry.dart';
import '../../services/watermark/watermark_logo_loader.dart';
import '../../state/providers.dart';
import 'multi_pass_preview.dart';

/// 水印边框预览组件
///
/// 使用 [WatermarkGeometry] 统一布局模型 + [FittedBox] 锁死比例：
/// - 内部画布为固定参考尺寸（由 geometry 决定），不随窗口拉伸改变排版
/// - [FittedBox] 将整块画布等比缩放适配 UI 容器
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

    // ── 几何计算 ──
    final srcW = state.uiImage.width;
    final srcH = state.uiImage.height;
    final cropAspect = params.crop.outAspectFor(
      srcW.toDouble(),
      srcH.toDouble(),
    );
    final hasLogo = watermarkHasLogo(config);
    final exifStr = resolveWatermarkExif(config, state.metadata);
    final showExif = watermarkShowExif(config, exifText: exifStr);

    final geometry = WatermarkGeometry.compute(
      imageAspectRatio: cropAspect,
      config: config,
      hasLogo: hasLogo,
      showExif: showExif,
    );

    final textColor = config.colorMode == WatermarkColorMode.light
        ? AppColors.textPrimary
        : Colors.black;

    // ── 渲染路径选择 ──
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
      return _WatermarkCanvas(
        geometry: geometry,
        config: config,
        textColor: textColor,
        imageLayer: _ComplexImageLayer(
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
          geometry: geometry,
        ),
        backgroundLayer: _buildBackground(
          config,
          geometry,
          state,
          params,
          lut,
          lutEnabled,
          ref,
        ),
        infoLayer: _InfoLayer(
          metadata: state.metadata,
          config: config,
          geometry: geometry,
          textColor: textColor,
          exifText: exifStr,
        ),
      );
    }

    // 简单路径
    return _WatermarkCanvas(
      geometry: geometry,
      config: config,
      textColor: textColor,
      imageLayer: _SimpleImageLayer(
        image: state.uiImage,
        params: params,
        crop: params.crop,
        lutTexture: lutEnabled ? lut.textureA : null,
        lutSize: lutEnabled ? lut.sizeA : 0,
        lutTextureB: lutEnabled ? lut.textureB : null,
        lutSizeB: lutEnabled ? lut.sizeB : 0,
        curveTexture: ref.watch(effectiveCurveTextureProvider),
        geometry: geometry,
      ),
      backgroundLayer: _buildBackground(
        config,
        geometry,
        state,
        params,
        lut,
        lutEnabled,
        ref,
      ),
      infoLayer: _InfoLayer(
        metadata: state.metadata,
        config: config,
        geometry: geometry,
        textColor: textColor,
        exifText: exifStr,
      ),
    );
  }

  // ── 背景层构建 ──

  static Widget? _buildBackground(
    WatermarkConfig config,
    WatermarkGeometry geometry,
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
    WidgetRef ref,
  ) {
    switch (config.backgroundType) {
      case BackgroundType.solidColor:
        return null; // 由 Container color 处理
      case BackgroundType.blurredOriginal:
        return _BlurredBackgroundLayer(
          image: state.uiImage,
          params: params,
          lutTexture: lutEnabled ? lut.textureA : null,
          lutSize: lutEnabled ? lut.sizeA : 0,
          lutTextureB: lutEnabled ? lut.textureB : null,
          lutSizeB: lutEnabled ? lut.sizeB : 0,
          curveTexture: ref.watch(effectiveCurveTextureProvider),
          blurSigma: config.blurRadius,
          canvasSize: geometry.canvasSize,
        );
      case BackgroundType.image:
        if (config.customBackgroundPath != null) {
          return _CustomImageBackground(filename: config.customBackgroundPath!);
        }
        return null;
    }
  }
}

// ──────────────────────────────────────────────────────────────
// 画布容器：FittedBox + 绝对定位 Stack
// ──────────────────────────────────────────────────────────────

class _WatermarkCanvas extends StatelessWidget {
  final WatermarkGeometry geometry;
  final WatermarkConfig config;
  final Color textColor;
  final Widget imageLayer;
  final Widget? backgroundLayer;
  final Widget? infoLayer;

  const _WatermarkCanvas({
    required this.geometry,
    required this.config,
    required this.textColor,
    required this.imageLayer,
    this.backgroundLayer,
    this.infoLayer,
  });

  @override
  Widget build(BuildContext context) {
    final shadowColor = Colors.black.withValues(
      alpha: config.shadowIntensity * 0.6,
    );
    final showShadow = config.shadowIntensity > 0.001;

    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        width: geometry.canvasSize.width,
        height: geometry.canvasSize.height,
        color: config.backgroundType == BackgroundType.solidColor
            ? config.backgroundColor
            : Colors.black,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Layer 0: 背景
            if (backgroundLayer != null)
              Positioned.fill(child: backgroundLayer!),

            // Layer 1: 信息层（在图片后方时）
            if (infoLayer != null && geometry.infoBehindImage)
              Positioned(
                left: geometry.infoRect.left,
                top: geometry.infoRect.top,
                width: geometry.infoRect.width,
                height: geometry.infoRect.height,
                child: infoLayer!,
              ),

            // Layer 2: 原图（圆角 + 阴影）
            Positioned(
              left: geometry.imageRect.left,
              top: geometry.imageRect.top,
              width: geometry.imageRect.width,
              height: geometry.imageRect.height,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(geometry.cornerRadius),
                  boxShadow: showShadow
                      ? [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: geometry.shadowBlur,
                            offset: Offset(0, geometry.shadowOffsetY),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(geometry.cornerRadius),
                  child: imageLayer,
                ),
              ),
            ),

            // Layer 1: 信息层（在图片前方 / 叠加模式时）
            if (infoLayer != null && !geometry.infoBehindImage)
              Positioned(
                left: geometry.infoRect.left,
                top: geometry.infoRect.top,
                width: geometry.infoRect.width,
                height: geometry.infoRect.height,
                child: infoLayer!,
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 2 简单路径：PreviewRenderer + 裁剪变换
// ──────────────────────────────────────────────────────────────

class _SimpleImageLayer extends ConsumerWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final CropParams crop;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;
  final WatermarkGeometry geometry;

  const _SimpleImageLayer({
    required this.image,
    required this.params,
    required this.crop,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    required this.geometry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetSize = geometry.imageRect.size;

    if (crop.isIdentity) {
      return SizedBox.fromSize(
        size: targetSize,
        child: PreviewRenderer(
          image: image,
          lutTexture: lutTexture,
          lutSize: lutSize,
          lutTextureB: lutTextureB,
          lutSizeB: lutSizeB,
          curveTexture: curveTexture,
        ),
      );
    }

    // 带裁剪 → 构建 transform 层级
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final orientedW = crop.orientationSwapsAxes ? imgH : imgW;
    final orientedH = crop.orientationSwapsAxes ? imgW : imgH;
    final scale = targetSize.width / (orientedW * crop.width);
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
              crop.orientation * math.pi / 2 + crop.straighten * math.pi / 180,
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

    return SizedBox.fromSize(
      size: targetSize,
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
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 2 复杂路径：MultiPassPreview
// ──────────────────────────────────────────────────────────────

class _ComplexImageLayer extends ConsumerWidget {
  final ui.FragmentProgram developProgram;
  final ui.FragmentProgram maskProgram;
  final ui.Image sourceImage;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;
  final ui.FragmentProgram? sharpenProgram;
  final ui.FragmentProgram? denoiseProgram;
  final WatermarkGeometry geometry;

  const _ComplexImageLayer({
    required this.developProgram,
    required this.maskProgram,
    required this.sourceImage,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    this.sharpenProgram,
    this.denoiseProgram,
    required this.geometry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVertical = MediaQuery.of(context).size.shortestSide < 600;
    final previewQ = ref.watch(previewQualityProvider);
    final (idle, dragging) = previewQ.edges(isVertical: isVertical);

    // 覆盖 idle/dragging 分辨率：以 geometry 中图片槽的较长边为准
    final slotLongest = math
        .max(geometry.imageRect.width, geometry.imageRect.height)
        .ceil();

    return SizedBox.fromSize(
      size: geometry.imageRect.size,
      child: MultiPassPreview(
        developProgram: developProgram,
        maskProgram: maskProgram,
        sourceImage: sourceImage,
        params: params,
        lutTexture: lutTexture,
        lutSize: lutSize,
        lutTextureB: lutTextureB,
        lutSizeB: lutSizeB,
        curveTexture: curveTexture,
        sharpenProgram: sharpenProgram,
        denoiseProgram: denoiseProgram,
        idleMaxEdge: slotLongest,
        draggingMaxEdge: (slotLongest * 0.5).ceil().clamp(200, dragging),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 0: 模糊原图背景
// ──────────────────────────────────────────────────────────────

class _BlurredBackgroundLayer extends ConsumerWidget {
  final ui.Image image;
  final AdjustmentParams params;
  final ui.Image? lutTexture;
  final int lutSize;
  final ui.Image? lutTextureB;
  final int lutSizeB;
  final ui.Image? curveTexture;
  final double blurSigma;
  final Size canvasSize;

  const _BlurredBackgroundLayer({
    required this.image,
    required this.params,
    this.lutTexture,
    this.lutSize = 0,
    this.lutTextureB,
    this.lutSizeB = 0,
    this.curveTexture,
    required this.blurSigma,
    required this.canvasSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDragging = ref.watch(isUserDraggingSliderProvider);
    final programAsync = ref.watch(shaderProgramProvider);

    return programAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (program) {
        final b = computeBlurParams(
          srcWidth: image.width.toDouble(),
          srcHeight: image.height.toDouble(),
          blurSigma: blurSigma,
          refCanvasWidth: canvasSize.width,
          refCanvasHeight: canvasSize.height,
          maxThumbEdge: isDragging ? 64.0 : 256.0,
        );

        return ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: b.compensatedSigma.clamp(0.0, 50.0),
              sigmaY: b.compensatedSigma.clamp(0.0, 50.0),
            ),
            child: SizedBox(
              width: b.thumbW.toDouble(),
              height: b.thumbH.toDouble(),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: image.width.toDouble(),
                  height: image.height.toDouble(),
                  child: PreviewRenderer(
                    image: image,
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
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final img = await loadWatermarkFileImage(widget.filename);
    if (mounted && img != null) {
      _image?.dispose();
      setState(() => _image = img);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return Container(color: AppColors.fallbackBg);
    }
    return RawImage(image: _image, fit: BoxFit.cover);
  }
}

// ──────────────────────────────────────────────────────────────
// Layer 1: Logo + EXIF 信息层
// ──────────────────────────────────────────────────────────────

class _InfoLayer extends StatelessWidget {
  final RawMetadata? metadata;
  final WatermarkConfig config;
  final WatermarkGeometry geometry;
  final Color textColor;
  final String? exifText;

  const _InfoLayer({
    required this.metadata,
    required this.config,
    required this.geometry,
    required this.textColor,
    this.exifText,
  });

  @override
  Widget build(BuildContext context) {
    if (!geometry.hasLogo && !geometry.hasExif) {
      return const SizedBox.shrink();
    }

    final exifStr = exifText;

    final fontWeight = fontWeightFromIndex(config.fontWeightIndex);
    final textStyle = TextStyle(
      fontSize: geometry.fontSize,
      fontWeight: fontWeight,
      color: textColor.withValues(alpha: config.textOpacity),
      fontFamily: config.fontFamily,
    );

    final hasLogo = watermarkHasLogo(config);

    return Padding(
      padding: EdgeInsets.all(geometry.textPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasLogo)
            Opacity(
              opacity: config.logoOpacity,
              child: _LogoImage(config: config, maxHeight: geometry.logoMaxH),
            ),
          if (hasLogo && exifStr != null)
            SizedBox(height: geometry.textPad / 2),
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
}

// ──────────────────────────────────────────────────────────────
// Logo 图片加载组件
// ──────────────────────────────────────────────────────────────

class _LogoImage extends StatefulWidget {
  final WatermarkConfig? config;
  final double maxHeight;

  const _LogoImage({this.config, required this.maxHeight});

  @override
  State<_LogoImage> createState() => _LogoImageState();
}

class _LogoImageState extends State<_LogoImage> {
  ui.Image? _image;
  int _loadGen = 0; // 防止并发加载覆盖

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LogoImage old) {
    super.didUpdateWidget(old);
    // 仅比较影响 Logo 加载的字段，避免调整其他水印参数时重建 Logo 导致闪烁
    final a = widget.config, b = old.config;
    final changed =
        a?.logoSource != b?.logoSource ||
        a?.logoBrand != b?.logoBrand ||
        a?.customLogoPath != b?.customLogoPath ||
        a?.colorMode != b?.colorMode;
    if (changed) _load(); // 先加载新图，不立即销毁旧图
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.config == null) return;
    final gen = ++_loadGen;
    final img = await WatermarkLogoLoader.load(widget.config!);
    if (!mounted || gen != _loadGen) {
      img?.dispose(); // 过期结果，丢弃
      return;
    }
    // 新图加载成功后才换掉旧图，消除中间空白帧
    final old = _image;
    _image = img;
    old?.dispose();
    setState(() {});
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

// ──────────────────────────────────────────────────────────────
// 辅助函数
// ──────────────────────────────────────────────────────────────
