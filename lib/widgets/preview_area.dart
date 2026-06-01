import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/raw_formats.dart';
import '../core/models/adjustment_params.dart';
import '../render/preview_renderer.dart';
import '../screens/folder_import_screen.dart';
import '../state/providers.dart';
import 'crop_overlay.dart';
import 'crop_panel.dart';
import 'local_mask_overlay.dart';
import 'multi_pass_preview.dart';

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
    return _buildCroppedPreview(state, params, lut, lutEnabled, ref);
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
                  ..translate(displaySize.width / 2, displaySize.height / 2, 0)
                  ..rotateZ(
                    draft.orientation * math.pi / 2 +
                        draft.straighten * math.pi / 180,
                  )
                  ..scale(draft.flipH ? -1.0 : 1.0, draft.flipV ? -1.0 : 1.0)
                  ..translate(-imgW * scale / 2, -imgH * scale / 2);

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
    final needFullPipeline = hasLocals || hasSharpen;

    final selectedLocalId = ref.watch(selectedLocalIdProvider);

    Widget wrapOverlay(Widget content, Size displaySize) {
      if (selectedLocalId == null) return content;
      return Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned.fill(
            child: LocalMaskOverlay(imageDisplaySize: displaySize),
          ),
        ],
      );
    }

    // 完整管线 带有local
    if (needFullPipeline) {
      final maskProgram = ref.watch(maskShaderProgramProvider).value;
      final develop = ref.watch(shaderProgramProvider).value;
      if (develop == null || maskProgram == null) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return GestureDetector(
        onTap: () => ref.read(fullscreenPreviewProvider.notifier).state = true,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final imgW = state.uiImage.width.toDouble();
            final imgH = state.uiImage.height.toDouble();
            final outAspect = params.crop.outAspectFor(imgW, imgH);
            final isVertical = MediaQuery.of(ctx).size.shortestSide < 600;
            final previewQ = ref.watch(previewQualityProvider);
            final (idle, dragging) = previewQ.edges(isVertical: isVertical);
            final box = applyBoxFit(
              BoxFit.contain,
              Size(outAspect, 1.0),
              constraints.biggest,
            ).destination;
            return Container(
              color: Colors.black,
              child: Center(
                child: SizedBox.fromSize(
                  size: box,
                  child: wrapOverlay(
                    MultiPassPreview(
                      developProgram: develop,
                      maskProgram: maskProgram,
                      sourceImage: state.uiImage,
                      params: params,
                      lutTexture: lutEnabled ? lut.textureA : null,
                      lutSize: lutEnabled ? lut.sizeA : 0,
                      lutTextureB: lutEnabled ? lut.textureB : null,
                      lutSizeB: lutEnabled ? lut.sizeB : 0,
                      curveTexture: ref.watch(effectiveCurveTextureProvider),
                      sharpenProgram: ref
                          .watch(sharpenShaderProgramProvider)
                          .value,
                      idleMaxEdge: idle,
                      draggingMaxEdge: dragging,
                    ),
                    box,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // 无 local 无锐化
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
          return GestureDetector(
            onTap: () =>
                ref.read(fullscreenPreviewProvider.notifier).state = true,
            child: Container(
              color: Colors.black,
              child: Center(
                child: SizedBox.fromSize(
                  size: fit.destination,
                  child: wrapOverlay(
                    PreviewRenderer(
                      image: image,
                      params: params,
                      lutTexture: lutEnabled ? lut.textureA : null,
                      lutSize: lutEnabled ? lut.sizeA : 0,
                      lutTextureB: lutEnabled ? lut.textureB : null,
                      lutSizeB: lutEnabled ? lut.sizeB : 0,
                      curveTexture: ref.watch(effectiveCurveTextureProvider),
                    ),
                    fit.destination,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // 无 local 无锐化 + 有裁剪：原 Transform 模拟裁剪
    return GestureDetector(
      onTap: () => ref.read(fullscreenPreviewProvider.notifier).state = true,
      child: Container(
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

            final matrix = Matrix4.identity()
              ..translate(box.width / 2, box.height / 2, 0)
              ..rotateZ(
                crop.orientation * math.pi / 2 +
                    crop.straighten * math.pi / 180,
              )
              ..scale(crop.flipH ? -1.0 : 1.0, crop.flipV ? -1.0 : 1.0)
              ..translate(
                -(crop.x + crop.width / 2) * renderedOrientedW,
                -(crop.y + crop.height / 2) * renderedOrientedH,
              );

            return Center(
              child: SizedBox.fromSize(
                size: box,
                child: wrapOverlay(
                  ClipRect(
                    child: Transform(
                      transform: matrix,
                      child: OverflowBox(
                        minWidth: renderedFullW,
                        maxWidth: renderedFullW,
                        minHeight: renderedFullH,
                        maxHeight: renderedFullH,
                        alignment: Alignment.topLeft,
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
                            curveTexture: ref.watch(
                              effectiveCurveTextureProvider,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  box,
                ),
              ),
            );
          },
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
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                );
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
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                  );
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