import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';

import '../../core/constants/raw_formats.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/models/crop_params.dart';
import '../../core/models/perspective_params.dart';
import '../../render/gpu_warmup.dart';
import '../../render/pass_config.dart';
import '../../render/preview_renderer.dart';
import '../../screens/folder_import_screen.dart';
import '../../state/providers.dart';
import 'color_picker_overlay.dart';
import 'crop_overlay.dart';
import 'crop_panel.dart';
import '../develop/sections/local/local_mask_overlay.dart';
import '../../brushes/brush_manifest.dart';
import '../../brushes/healing/healing_overlay.dart';
import '../../brushes/spot_heal/spot_heal_overlay.dart';
import '../../brushes/dodge_burn/dodge_burn_overlay.dart';
import '../../brushes/clone_stamp/clone_stamp_overlay.dart';
import 'multi_pass_preview.dart';
import 'split_compare_view.dart';
import 'sr_preview_overlay.dart';
import 'watermark_preview.dart';

class PreviewArea extends ConsumerWidget {
  const PreviewArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(imageNotifierProvider);

    return imageAsync.when(
      loading: () {
        final prev = imageAsync.value;
        if (prev != null) {
          return _PreviewContent(key: ObjectKey(prev.uiImage), state: prev);
        }
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      error: (e, _) => _CenterMessage(
        icon: Icons.warning_amber_rounded,
        color: AppColors.semanticWarning,
        title: tr("decodeFailed"),
        body: e.toString(),
      ),
      data: (state) {
        if (state == null) return _buildEmpty(context, ref);
        return _PreviewContent(key: ObjectKey(state.uiImage), state: state);
      },
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: AppColors.disabledText,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              if (Platform.isAndroid) {
                final navigator = Navigator.of(context);
                final notifier = ref.read(shotsNotifierProvider.notifier);
                final paths = await openFolderImport(navigator);
                if (paths != null && paths.isNotEmpty) {
                  notifier.addFiles(paths);
                }
              } else {
                final notifier = ref.read(shotsNotifierProvider.notifier);
                final result = await FilePicker.pickFiles();
                if (result == null || result.files.isEmpty) return;
                final paths = result.files
                    .map((f) => f.path)
                    .whereType<String>()
                    .toList();
                if (paths.isNotEmpty) {
                  notifier.addFiles(paths);
                }
              }
            },
            icon: Icon(
              Platform.isAndroid
                  ? Icons.folder_copy_outlined
                  : Icons.folder_open,
            ),
            label: Text(
              Platform.isAndroid ? tr("folderImport") : tr("imageChoose"),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: _FormatMarquee(text: RawFormats.displayList),
          ),
        ],
      ),
    );
  }
}

// _PreviewContent — 图片内容渲染控件
class _PreviewContent extends ConsumerStatefulWidget {
  final DecodedImageState state;
  const _PreviewContent({super.key, required this.state});

  @override
  ConsumerState<_PreviewContent> createState() => _PreviewContentState();
}

class _PreviewContentState extends ConsumerState<_PreviewContent> {
  @override
  void initState() {
    super.initState();
    _scheduleWarmup();
  }

  void _scheduleWarmup() {
    ref.read(shaderWarmupProvider.future).then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _triggerWarmup();
      });
    });
  }

  void _triggerWarmup() {
    // 如果当前走 FullPipeline 路径，预热由 MultiPassPreview 负责
    final params = ref.read(effectiveParamsProvider);
    if (needsFullPipeline(params)) return;

    final brushProgs = ref.read(brushShaderProgramsProvider).value ?? {};
    final composeProg = ref.read(composeShaderProgramProvider).value;

    if (brushProgs.values.every((p) => p == null) && composeProg == null) {
      return;
    }

    final src = widget.state.uiImage;
    const maxEdge = 2048;
    final longest = math.max(src.width, src.height);
    final scale = longest > maxEdge ? maxEdge / longest : 1.0;
    final tw = (src.width * scale).round();
    final th = (src.height * scale).round();

    ui.Image clone;
    try {
      clone = src.clone();
    } catch (_) {
      return;
    }

    final tasks = buildWarmupTasks(
      brushPrograms: brushProgs,
      composeProgram: composeProg,
      developOutput: clone,
      targetWidth: tw,
      targetHeight: th,
    );

    if (tasks.isEmpty) {
      clone.dispose();
      return;
    }

    runWarmupChain(tasks, clone, isMounted: () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    final params = ref.watch(effectiveParamsProvider);
    final lutState = ref.watch(lutNotifierProvider);
    final lutEnabled = ref.watch(effectiveLutEnabledProvider);
    final cropEditMode = ref.watch(cropEditModeProvider);

    if (cropEditMode) {
      return _buildCropEdit(widget.state, params, lutState, lutEnabled, ref);
    }
    final compareMode = ref.watch(compareViewModeProvider);
    if (compareMode == CompareViewMode.split) {
      return _buildSplitCompare(widget.state, lutState, lutEnabled, ref);
    }
    final watermarkOn = ref.watch(
      watermarkConfigProvider.select((c) => c.enabled),
    );
    if (watermarkOn) {
      return _buildWatermarkPreview(
        widget.state,
        params,
        lutState,
        lutEnabled,
        ref,
      );
    }
    return _buildCroppedPreview(
      widget.state,
      params,
      lutState,
      lutEnabled,
      ref,
    );
  }

  Widget _buildSplitCompare(
    DecodedImageState state,
    LutState lut,
    bool lutEnabled,
    WidgetRef ref,
  ) {
    final develop = ref.watch(shaderProgramProvider).value;
    final maskProgram = ref.watch(maskShaderProgramProvider).value;
    if (develop == null || maskProgram == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final effective = ref.watch(effectiveParamsProvider);
    final splitParams = effective.crop.isIdentity
        ? effective
        : effective.copyWith(crop: CropParams.identity);
    return Container(
      color: Colors.black,
      child: SplitCompareView(
        image: state.uiImage,
        params: splitParams,
        developProgram: develop,
        maskProgram: maskProgram,
        lutA: lutEnabled ? lut.textureA : null,
        lutSizeA: lutEnabled ? lut.sizeA : 0,
        lutB: lutEnabled ? lut.textureB : null,
        lutSizeB: lutEnabled ? lut.sizeB : 0,
        curve: ref.watch(effectiveCurveTextureProvider),
        sharpenProgram: ref.watch(sharpenShaderProgramProvider).value,
        denoiseProgram: ref.watch(denoiseShaderProgramProvider).value,
        perspectiveProgram: ref.watch(perspectiveShaderProgramProvider).value,
        lensCorrectProgram: ref.watch(lensCorrectShaderProgramProvider).value,
      ),
    );
  }

  Widget _buildCropEdit(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
    WidgetRef ref,
  ) {
    final draft = ref.watch(cropDraftProvider);
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final develop = ref.watch(shaderProgramProvider).value;
                final maskProgram = ref.watch(maskShaderProgramProvider).value;
                if (develop == null || maskProgram == null) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final previewParams = params.copyWith(
                  crop: CropParams.identity,
                  perspective: PerspectiveParams.identity,
                );

                final imgW = state.uiImage.width.toDouble();
                final imgH = state.uiImage.height.toDouble();
                final orientedW = draft.orientationSwapsAxes ? imgH : imgW;
                final orientedH = draft.orientationSwapsAxes ? imgW : imgH;
                final fit = applyBoxFit(
                  BoxFit.contain,
                  Size(orientedW, orientedH),
                  constraints.biggest,
                );
                final displaySize = fit.destination;
                final scale = displaySize.width / orientedW;
                final matrix = Matrix4.identity()
                  ..translateByDouble(
                    displaySize.width / 2,
                    displaySize.height / 2,
                    0,
                    1.0,
                  )
                  ..rotateZ(
                    draft.orientation * math.pi / 2 +
                        draft.straighten * math.pi / 180,
                  )
                  ..scaleByDouble(
                    draft.flipH ? -1.0 : 1.0,
                    draft.flipV ? -1.0 : 1.0,
                    1.0,
                    1.0,
                  )
                  ..translateByDouble(
                    -imgW * scale / 2,
                    -imgH * scale / 2,
                    0,
                    1.0,
                  );
                Widget imageContent = SizedBox.fromSize(
                  size: displaySize,
                  child: ClipRect(
                    child: Transform(
                      transform: matrix,
                      child: OverflowBox(
                        minWidth: imgW * scale,
                        maxWidth: imgW * scale,
                        minHeight: imgH * scale,
                        maxHeight: imgH * scale,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: imgW * scale,
                          height: imgH * scale,
                          child: MultiPassPreview(
                            developProgram: develop,
                            maskProgram: maskProgram,
                            sourceImage: state.uiImage,
                            params: previewParams,
                            lutTexture: lutEnabled ? lut.textureA : null,
                            lutSize: lutEnabled ? lut.sizeA : 0,
                            lutTextureB: lutEnabled ? lut.textureB : null,
                            lutSizeB: lutEnabled ? lut.sizeB : 0,
                            curveTexture: ref.watch(
                              effectiveCurveTextureProvider,
                            ),
                            sharpenProgram: ref
                                .watch(sharpenShaderProgramProvider)
                                .value,
                            denoiseProgram: ref
                                .watch(denoiseShaderProgramProvider)
                                .value,
                            perspectiveProgram: ref
                                .watch(perspectiveShaderProgramProvider)
                                .value,
                            lensCorrectProgram: ref
                                .watch(lensCorrectShaderProgramProvider)
                                .value,
                            spotRemoveProgram: ref
                                .watch(spotRemoveShaderProgramProvider)
                                .value,
                            healingProgram: ref
                                .watch(healingShaderProgramProvider)
                                .value,
                            idleMaxEdge: 2400,
                            draggingMaxEdge: 800,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                imageContent = _wrapPreviewContent(
                  ref,
                  imageContent,
                  displaySize,
                  state,
                  params,
                  lut,
                  lutEnabled,
                );
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    imageContent,
                    SizedBox.fromSize(
                      size: displaySize,
                      child: CropOverlay(imageDisplaySize: displaySize),
                    ),
                  ],
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: CropPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildCroppedPreview(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
    WidgetRef ref,
  ) {
    final needFullPipeline = needsFullPipeline(params);

    if (needFullPipeline) {
      final maskProgram = ref.watch(maskShaderProgramProvider).value;
      final develop = ref.watch(shaderProgramProvider).value;
      if (develop == null || maskProgram == null) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return LayoutBuilder(
        builder: (ctx, constraints) {
          final isVertical = MediaQuery.of(ctx).size.shortestSide < 600;
          final previewQ = ref.watch(previewQualityProvider);
          final (idle, dragging) = previewQ.edges(isVertical: isVertical);
          final imgW = state.uiImage.width.toDouble();
          final imgH = state.uiImage.height.toDouble();
          final outAspect = params.crop.outAspectFor(imgW, imgH);
          final box = applyBoxFit(
            BoxFit.contain,
            Size(outAspect, 1.0),
            constraints.biggest,
          ).destination;
          final preview = MultiPassPreview(
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
            perspectiveProgram: ref
                .watch(perspectiveShaderProgramProvider)
                .value,
            lensCorrectProgram: ref
                .watch(lensCorrectShaderProgramProvider)
                .value,
            spotRemoveProgram: ref.watch(spotRemoveShaderProgramProvider).value,
            healingProgram: ref.watch(healingShaderProgramProvider).value,
            idleMaxEdge: idle,
            draggingMaxEdge: dragging,
          );
          return _wrapPreviewContent(
            ref,
            SizedBox.fromSize(size: box, child: preview),
            box,
            state,
            params,
            lut,
            lutEnabled,
          );
        },
      );
    }

    final crop = params.crop;
    final image = state.uiImage;

    if (crop.isIdentity) {
      return LayoutBuilder(
        builder: (ctx, constraints) {
          final fit = applyBoxFit(
            BoxFit.contain,
            Size(image.width.toDouble(), image.height.toDouble()),
            constraints.biggest,
          );
          return _wrapPreviewContent(
            ref,
            SizedBox.fromSize(
              size: fit.destination,
              child: PreviewRenderer(
                image: image,
                lutTexture: lutEnabled ? lut.textureA : null,
                lutSize: lutEnabled ? lut.sizeA : 0,
                lutTextureB: lutEnabled ? lut.textureB : null,
                lutSizeB: lutEnabled ? lut.sizeB : 0,
                curveTexture: ref.watch(effectiveCurveTextureProvider),
              ),
            ),
            fit.destination,
            state,
            params,
            lut,
            lutEnabled,
          );
        },
      );
    }

    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final imgW = image.width.toDouble();
          final imgH = image.height.toDouble();
          final outAspect = crop.outAspectFor(imgW, imgH);
          final box = applyBoxFit(
            BoxFit.contain,
            Size(outAspect, 1.0),
            constraints.biggest,
          ).destination;
          final orientedW = crop.orientationSwapsAxes ? imgH : imgW;
          final orientedH = crop.orientationSwapsAxes ? imgW : imgH;
          final scale = box.width / (orientedW * crop.width);
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
          return _wrapPreviewContent(
            ref,
            SizedBox.fromSize(
              size: box,
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
            ),
            box,
            state,
            params,
            lut,
            lutEnabled,
          );
        },
      ),
    );
  }

  Widget _buildWatermarkPreview(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
    WidgetRef ref,
  ) {
    return Container(
      color: Colors.black,
      child: Center(
        child: WatermarkPreview(
          state: state,
          params: params,
          lut: lut,
          lutEnabled: lutEnabled,
        ),
      ),
    );
  }

  Widget? _wrapColorPicker(
    WidgetRef ref,
    Widget content,
    Size displaySize,
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
  ) {
    final pickerOn = ref.watch(colorPickerModeProvider);
    if (!pickerOn) return null;
    final develop = ref.watch(shaderProgramProvider).value;
    final maskProgram = ref.watch(maskShaderProgramProvider).value;
    if (develop == null || maskProgram == null) {
      return Container(
        color: Colors.black,
        child: Center(child: content),
      );
    }
    final picked = ref.watch(pickedColorProvider);
    return Container(
      color: Colors.black,
      child: Center(
        child: SizedBox.fromSize(
          size: displaySize,
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned.fill(
                child: ColorPickerOverlay(
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
                  displaySize: displaySize,
                ),
              ),
              if (picked != null)
                Builder(
                  builder: (_) {
                    const readoutW = 140.0;
                    const readoutH = 56.0;
                    const gap = 16.0;
                    final cursorX = picked.nx * displaySize.width;
                    final cursorY = picked.ny * displaySize.height;
                    final placeLeft = cursorX > displaySize.width / 2;
                    final placeAbove = cursorY > displaySize.height / 2;
                    final left = placeLeft
                        ? cursorX - gap - readoutW
                        : cursorX + gap;
                    final top = placeAbove
                        ? cursorY - gap - readoutH
                        : cursorY + gap;
                    return Positioned(
                      left: left.clamp(0.0, displaySize.width - readoutW),
                      top: top.clamp(0.0, displaySize.height - readoutH),
                      child: _ColorReadout(picked: picked),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 若画笔活跃则构建 overlay widget，否则返回 null
  ///
  /// 每支画笔有独立的状态形状和 overlay 类，按 [BrushManifest.id] 分发
  /// 新增画笔在此添加 case
  Widget? _buildOverlayIfActive(
    BrushManifest m,
    WidgetRef ref,
    Size displaySize,
    DecodedImageState state,
    AdjustmentParams params,
  ) {
    final overlaySource = ref.watch(developOutputProvider) ?? state.uiImage;
    switch (m.id) {
      case 'spot_removal':
        final st = ref.watch(spotRemoveStateProvider);
        if (st.mode != SpotRemoveMode.active) return null;
        return SpotRemoveOverlay(
          imageDisplaySize: displaySize,
          crop: params.crop,
          sourceWidth: state.uiImage.width,
          sourceHeight: state.uiImage.height,
          sourceImage: overlaySource,
        );
      case 'healing':
        final st = ref.watch(healingStateProvider);
        if (st.mode != HealingMode.active &&
            !HealingOverlayState.hasPendingPreview) {
          return null;
        }
        return HealingOverlay(
          imageDisplaySize: displaySize,
          crop: params.crop,
          sourceWidth: state.uiImage.width,
          sourceHeight: state.uiImage.height,
          sourceImage: overlaySource,
          interactive: st.mode == HealingMode.active,
        );
      case 'spot_heal':
        final st = ref.watch(spotHealStateProvider);
        if (st.mode != SpotHealMode.active) return null;
        return SpotHealOverlay(
          imageDisplaySize: displaySize,
          crop: params.crop,
          sourceWidth: state.uiImage.width,
          sourceHeight: state.uiImage.height,
          sourceImage: overlaySource,
        );
      case 'dodge_burn':
        final st = ref.watch(dodgeBurnStateProvider);
        if (st.brushMode != DodgeBurnBrushMode.active) return null;
        return DodgeBurnOverlay(
          imageDisplaySize: displaySize,
          crop: params.crop,
          sourceWidth: state.uiImage.width,
          sourceHeight: state.uiImage.height,
          sourceImage: overlaySource,
        );
      default:
        return null;
    }
  }

  Widget _wrapPreviewContent(
    WidgetRef ref,
    Widget content,
    Size displaySize,
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
  ) {
    // 画笔 overlays — 通过 manifest 循环，统一的 Stack 包裹模式
    for (final m in brushManifests) {
      final overlay = _buildOverlayIfActive(m, ref, displaySize, state, params);
      if (overlay != null) {
        // spot_heal 和 dodge_burn 没有 committed preview 生命周期，跳过 watch
        if (m.id != 'spot_heal' && m.id != 'dodge_burn') {
          ref.watch(renderedPreviewGenerationProvider);
        }
        content = SizedBox.fromSize(
          size: displaySize,
          child: Stack(
            children: [
              content,
              Positioned.fill(child: overlay),
            ],
          ),
        );
      }
    }

    final selectedLocalId = ref.watch(selectedLocalIdProvider);
    if (selectedLocalId != null) {
      return _withSrOverlay(
        ref,
        Container(
          color: Colors.black,
          child: Center(
            child: GestureDetector(
              onTap: () =>
                  ref.read(fullscreenPreviewProvider.notifier).state = true,
              child: SizedBox.fromSize(
                size: displaySize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    content,
                    Positioned.fill(
                      child: LocalMaskOverlay(imageDisplaySize: displaySize),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        params,
        displaySize,
        state.uiImage,
      );
    }
    final picker = _wrapColorPicker(
      ref,
      content,
      displaySize,
      state,
      params,
      lut,
      lutEnabled,
    );
    if (picker != null) {
      return _withSrOverlay(ref, picker, params, displaySize, state.uiImage);
    }
    return _withSrOverlay(
      ref,
      Container(
        color: Colors.black,
        child: Center(
          child: _ZoomableView(
            onTapNoZoom: () =>
                ref.read(fullscreenPreviewProvider.notifier).state = true,
            child: content,
          ),
        ),
      ),
      params,
      displaySize,
      state.uiImage,
    );
  }

  /// 超分辨率预览小窗
  Widget _withSrOverlay(
    WidgetRef ref,
    Widget child,
    AdjustmentParams params,
    Size displaySize,
    ui.Image sourceImage,
  ) {
    if (!params.srEnabled || !ref.watch(srPreviewEnabledProvider)) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          right: 8,
          bottom: 8,
          child: SrPreviewOverlay(
            displaySize: displaySize,
            sourceImage: sourceImage,
          ),
        ),
      ],
    );
  }
}

class _FormatMarquee extends StatefulWidget {
  final String text;
  const _FormatMarquee({required this.text});

  @override
  State<_FormatMarquee> createState() => _FormatMarqueeState();
}

class _FormatMarqueeState extends State<_FormatMarquee>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker;
  double _offset = 0;
  Duration? _last;

  static const _speed = 30.0;
  static const _gap = ' · ';

  static final _style = TextStyle(
    fontSize: 11,
    color: AppColors.disabledText,
    fontFamily: 'monospace',
  );

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) {
      _last = null;
      return;
    }
    final dt = _last == null ? 0.0 : (elapsed - _last!).inMicroseconds / 1e6;
    _last = elapsed;
    _offset += _speed * dt;
    if (_offset > max) _offset -= max;
    _scroll.jumpTo(_offset);
  }

  double _measure(String s, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final avail = constraints.maxWidth;
          final textW = _measure(widget.text, avail);
          final overflow = textW > avail;

          if (!overflow) {
            return Center(child: Text(widget.text, style: _style, maxLines: 1));
          }
          final doubled = '${widget.text}$_gap${widget.text}$_gap';
          return ListView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            children: [Text(doubled, style: _style, maxLines: 1)],
          );
        },
      ),
    );
  }
}

class _CenterMessage extends ConsumerWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _CenterMessage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SelectableText(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mediumText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                if (Platform.isAndroid) {
                  final navigator = Navigator.of(context);
                  final notifier = ref.read(shotsNotifierProvider.notifier);
                  final paths = await openFolderImport(navigator);
                  if (paths != null && paths.isNotEmpty) {
                    notifier.addFiles(paths);
                  }
                } else {
                  final notifier = ref.read(shotsNotifierProvider.notifier);
                  final result = await FilePicker.pickFiles();
                  if (result == null || result.files.isEmpty) return;
                  final paths = result.files
                      .map((f) => f.path)
                      .whereType<String>()
                      .toList();
                  if (paths.isNotEmpty) {
                    notifier.addFiles(paths);
                  }
                }
              },
              icon: Icon(
                Platform.isAndroid
                    ? Icons.folder_copy_outlined
                    : Icons.folder_open,
              ),
              label: Text(
                Platform.isAndroid ? tr("folderImport") : tr("imageChoose"),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ZoomableView extends StatefulWidget {
  final Widget child;
  final VoidCallback onTapNoZoom; // 未缩放时单击 → 全屏
  const _ZoomableView({required this.child, required this.onTapNoZoom});

  @override
  State<_ZoomableView> createState() => _ZoomableViewState();
}

class _ZoomableViewState extends State<_ZoomableView> {
  final _tc = TransformationController();
  static const _min = 1.0;
  static const _max = 8.0;

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _handleScroll(PointerScrollEvent e, Size viewport) {
    // 以鼠标位置为中心缩放
    final delta = -e.scrollDelta.dy;
    final factor = delta > 0 ? 1.15 : 1 / 1.15;
    final newScale = (_scale * factor).clamp(_min, _max);
    final actualFactor = newScale / _scale;
    if (actualFactor == 1.0) return;

    final focal = e.localPosition;
    final m = _tc.value.clone();
    // 焦点处缩放
    m
      ..translateByDouble(focal.dx, focal.dy, 0, 1.0)
      ..scaleByDouble(actualFactor, actualFactor, 1.0, 1.0)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1.0);
    _tc.value = m;
    setState(() {});
  }

  void _reset() {
    _tc.value = Matrix4.identity();
    setState(() {});
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Listener(
          onPointerSignal: (s) {
            if (s is PointerScrollEvent) _handleScroll(s, constraints.biggest);
          },
          child: GestureDetector(
            onDoubleTap: _scale > 1.01 ? _reset : null, // 放大状态双击复位
            onTap: _scale <= 1.01 ? widget.onTapNoZoom : null, // 未放大进全屏
            child: InteractiveViewer(
              transformationController: _tc,
              minScale: _min,
              maxScale: _max,
              panEnabled: true,
              scaleEnabled: true,
              clipBehavior: Clip.hardEdge,
              onInteractionEnd: (_) => setState(() {}),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class _ColorReadout extends StatelessWidget {
  final PickedColor picked;
  const _ColorReadout({required this.picked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 色块
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color.fromARGB(255, picked.r, picked.g, picked.b),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.disabledText),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'R${picked.r} G${picked.g} B${picked.b}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${picked.hex}  L${picked.luma}',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: AppColors.mediumText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
