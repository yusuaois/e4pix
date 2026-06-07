import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';

import '../../core/constants/raw_formats.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/models/crop_params.dart';
import '../../render/preview_renderer.dart';
import '../../screens/folder_import_screen.dart';
import '../../state/providers.dart';
import 'color_picker_overlay.dart';
import 'crop_overlay.dart';
import 'crop_panel.dart';
import '../local/local_mask_overlay.dart';
import 'multi_pass_preview.dart';
import 'split_compare_view.dart';

// Preview area
class PreviewArea extends ConsumerWidget {
  const PreviewArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(imageNotifierProvider);
    final params = ref.watch(effectiveParamsProvider);
    final lutState = ref.watch(lutNotifierProvider);
    final lutEnabled = ref.watch(effectiveLutEnabledProvider);
    final cropEditMode = ref.watch(cropEditModeProvider);

    return imageAsync.when(
      loading: () => imageAsync.value == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _buildBody(
              imageAsync.value!,
              params,
              lutState,
              lutEnabled,
              cropEditMode,
              ref,
            ),
      error: (e, _) => _CenterMessage(
        icon: Icons.warning_amber_rounded,
        color: Colors.orangeAccent,
        title: tr("decodeFailed"),
        body: e.toString(),
      ),
      data: (state) {
        if (state == null) return _buildEmpty(context, ref);
        return _buildBody(
          state,
          params,
          lutState,
          lutEnabled,
          cropEditMode,
          ref,
        );
      },
    );
  }

  Widget _buildBody(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
    bool cropMode,
    WidgetRef ref,
  ) {
    if (cropMode) return _buildCropEdit(state, params, lut, lutEnabled, ref);
    final compareMode = ref.watch(compareViewModeProvider);
    if (compareMode == CompareViewMode.split) {
      return _buildSplitCompare(state, lut, lutEnabled, ref);
    }
    return _buildCroppedPreview(state, params, lut, lutEnabled, ref);
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

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.fromSize(
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
                              child: PreviewRenderer(
                                image: state.uiImage,
                                params: params,
                                lutTexture: lutEnabled ? lut.textureA : null,
                                lutSize: lutEnabled ? lut.sizeA : 0,
                                lutTextureB: lutEnabled ? lut.textureB : null,
                                lutSizeB: lutEnabled ? lut.sizeB : 0,
                                curveTexture: ref.watch(
                                  effectiveCurveTextureProvider,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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

  /// 取色模式包装：把预览内容 + 取色层 + 读数浮层组合。
  /// [content] 该路径的预览内容；[displaySize] 图片实际显示矩形（裁剪后比例）。
  /// 非取色模式返回 null（调用方走原 _ZoomableView 分支）。
  Widget? _wrapColorPicker({
    required WidgetRef ref,
    required Widget content,
    required Size displaySize,
    required DecodedImageState state,
    required AdjustmentParams params,
    required LutState lut,
    required bool lutEnabled,
  }) {
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

  /// 普通模式：显示已裁剪的画面（OverflowBox + Transform 模拟裁剪）
  Widget _buildCroppedPreview(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
    WidgetRef ref,
  ) {
    final hasLocals = params.locals.any(
      (l) => l.enabled && !l.params.isNeutral,
    );
    final hasSharpen = params.sharpenAmount > 0.001;
    final hasDenoise =
        params.denoiseLuma > 0.001 || params.denoiseColor > 0.001;
    final needFullPipeline = hasLocals || hasSharpen || hasDenoise;

    // ============ 完整管线（local / 锐化 / 降噪）============
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
            idleMaxEdge: idle,
            draggingMaxEdge: dragging,
          );

          return _wrapPreviewContent(
            ref: ref,
            content: SizedBox.fromSize(size: box, child: preview),
            displaySize: box,
            state: state,
            params: params,
            lut: lut,
            lutEnabled: lutEnabled,
          );
        },
      );
    }

    final crop = params.crop;
    final image = state.uiImage;

    // ============ 无 local 无锐化 + 无裁剪 ============
    if (crop.isIdentity) {
      return LayoutBuilder(
        builder: (ctx, constraints) {
          final fit = applyBoxFit(
            BoxFit.contain,
            Size(image.width.toDouble(), image.height.toDouble()),
            constraints.biggest,
          );
          return _wrapPreviewContent(
            ref: ref,
            content: SizedBox.fromSize(
              size: fit.destination,
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
            displaySize: fit.destination,
            state: state,
            params: params,
            lut: lut,
            lutEnabled: lutEnabled,
          );
        },
      );
    }

    // ============ 无 local 无锐化 + 有裁剪 ============
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

          // 把原图旋转成"完整 oriented 图" renderedOrientedW × H
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

          // 在 oriented 图上切 crop 矩形
          return _wrapPreviewContent(
            ref: ref,
            content: SizedBox.fromSize(
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
            displaySize: box,
            state: state,
            params: params,
            lut: lut,
            lutEnabled: lutEnabled,
          );
        },
      ),
    );
  }

  /// 预览包装：蒙版编辑 → 取色 → 缩放查看
  Widget _wrapPreviewContent({
    required WidgetRef ref,
    required Widget content,
    required Size displaySize,
    required DecodedImageState state,
    required AdjustmentParams params,
    required LutState lut,
    required bool lutEnabled,
  }) {
    final selectedLocalId = ref.watch(selectedLocalIdProvider);

    // 蒙版编辑中
    if (selectedLocalId != null) {
      return Container(
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
      );
    }

    // 取色模式
    final picker = _wrapColorPicker(
      ref: ref,
      content: content,
      displaySize: displaySize,
      state: state,
      params: params,
      lut: lut,
      lutEnabled: lutEnabled,
    );
    if (picker != null) return picker;

    // 纯查看
    return Container(
      color: Colors.black,
      child: Center(
        child: _ZoomableView(
          onTapNoZoom: () =>
              ref.read(fullscreenPreviewProvider.notifier).state = true,
          child: content,
        ),
      ),
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
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              if (Platform.isAndroid) {
                final paths = await openFolderImport(context);
                if (paths != null && paths.isNotEmpty) {
                  ref.read(shotsNotifierProvider.notifier).addFiles(paths);
                }
              } else {
                final result = await FilePicker.pickFiles();
                if (result == null || result.files.isEmpty) return;
                final paths = result.files
                    .map((f) => f.path)
                    .whereType<String>()
                    .toList();
                if (paths.isNotEmpty) {
                  ref.read(shotsNotifierProvider.notifier).addFiles(paths);
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
    color: Colors.white.withValues(alpha: 0.4),
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
                  color: Colors.white.withValues(alpha: 0.7),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                if (Platform.isAndroid) {
                  final paths = await openFolderImport(context);
                  if (paths != null && paths.isNotEmpty) {
                    ref.read(shotsNotifierProvider.notifier).addFiles(paths);
                  }
                } else {
                  final result = await FilePicker.pickFiles();
                  if (result == null || result.files.isEmpty) return;
                  final paths = result.files
                      .map((f) => f.path)
                      .whereType<String>()
                      .toList();
                  if (paths.isNotEmpty) {
                    ref.read(shotsNotifierProvider.notifier).addFiles(paths);
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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
                  color: Colors.white,
                ),
              ),
              Text(
                '${picked.hex}  L${picked.luma}',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
