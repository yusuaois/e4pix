import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models/adjustment_params.dart';
import '../core/models/tethered_shot.dart';
import '../native/raw_bridge.dart';
import '../render/exporter.dart';
import '../render/preview_renderer.dart';
import '../services/ai/ai_color_service.dart';
import '../services/ai/ai_input_renderer.dart';
import '../services/ai/ai_settings.dart';
import '../state/providers.dart';
import '../widgets/adjustment_panel.dart';
import '../widgets/ai_settings_dialog.dart';
import '../widgets/ai_suggestion_dialog.dart';
import '../widgets/camera_picker_dialog.dart';
import '../widgets/compare_button.dart';
import '../widgets/crop_overlay.dart';
import '../widgets/crop_panel.dart';
import '../widgets/develop_sections.dart';
import '../widgets/histogram_panel.dart';
import '../widgets/preset_bar.dart';
import '../widgets/tether_widgets.dart';

class DevelopScreen extends ConsumerStatefulWidget {
  const DevelopScreen({super.key});
  @override
  ConsumerState<DevelopScreen> createState() => _DevelopScreenState();
}

class _DevelopScreenState extends ConsumerState<DevelopScreen> {
  // —— 纯 UI-local 状态 ——
  String _libRawVersion = '';
  String? _libRawError;
  Offset _histogramPosition = const Offset(8, 8);
  static const _miniHistogramW = 140.0;
  static const _miniHistogramH = 70.0;

  @override
  void initState() {
    super.initState();
    _libRawVersion = tr('loading');
    _probeFfi();
  }

  void _probeFfi() {
    try {
      final v = RawBridge.libRawVersion();
      if (mounted) setState(() => _libRawVersion = v);
    } catch (e) {
      if (mounted) {
        setState(() {
          _libRawVersion = tr('FFIFailed');
          _libRawError = e.toString();
        });
      }
    }
  }

  // 动作写 notifier
  Future<void> _pickAndDecode() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path != null) {
      ref.read(activeFilePathProvider.notifier).set(path);
    }
  }

  Future<void> _startFolderTether() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: tr('tetherFolderChoose'),
    );
    if (folder == null || folder.isEmpty) return;
    try {
      await ref.read(tetherSessionNotifierProvider.notifier).start(folder);
    } catch (e) {
      _snack(tr('tetherFailed', args: [e.toString()]));
    }
  }

  Future<void> _startCameraTether() async {
    final controller = CameraNotifier.createController();
    final pick = await showDialog<CameraPickResult>(
      context: context,
      builder: (_) => CameraPickerDialog(controller: controller),
    );
    if (pick == null) return;
    try {
      await ref
          .read(cameraNotifierProvider.notifier)
          .start(
            controller: controller,
            camera: pick.camera,
            saveFolder: pick.saveFolder,
          );
    } catch (e) {
      _snack(tr('cameraError', args: [e.toString()]));
    }
  }

  Future<void> _stopAllTether() async {
    final camActive = ref.read(cameraNotifierProvider).isActive;
    if (camActive) {
      await ref.read(cameraNotifierProvider.notifier).stop();
    }
    await ref.read(tetherSessionNotifierProvider.notifier).stop();
  }

  void _onParamsChanged(AdjustmentParams p) {
    ref.read(currentParamsNotifierProvider.notifier).update(p);
  }

  void _togglePreserve(bool v) {
    ref.read(preserveParamsProvider.notifier).set(v);
  }

  void _onThumbTap(TetheredShot shot) {
    final selection = ref.read(exportSelectionNotifierProvider);
    if (selection.multiSelectMode) {
      ref.read(exportSelectionNotifierProvider.notifier).toggleShot(shot.path);
    } else {
      ref.read(selectShotProvider)(shot);
    }
  }

  // AI Suggestion (manual + auto)
  Future<void> _showAISettings() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => const AISettingsDialog(),
    );
    final auto = await AISettings.getAutoAI();
    ref.read(aiAutoNotifierProvider.notifier).setEnabled(auto);
  }

  Future<void> _showAISuggestion() async {
    final hasKey = (await AISettings.getApiKey())?.isNotEmpty ?? false;
    if (!hasKey) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => const AISettingsDialog(),
      );
      if (ok != true) return;
      final nowHasKey = (await AISettings.getApiKey())?.isNotEmpty ?? false;
      if (!nowHasKey) return;
    }
    if (!mounted) return;

    final program = ref.read(shaderProgramProvider).value;
    final image = ref.read(imageNotifierProvider).value;
    if (program == null || image == null) return;

    final result = await showDialog<AIColorSuggestion>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AISuggestionDialog(
        currentParams: ref.read(currentParamsNotifierProvider),
        renderPreviewToFile: () async {
          final lut = ref.read(lutNotifierProvider);
          return AIInputRenderer.renderToTempFile(
            program: program,
            sourceImage: image.uiImage,
            params: ref.read(currentParamsNotifierProvider),
            lutTexture: lut.texture,
            lutSize: lut.size,
            maxEdge: await AISettings.getMaxEdge(),
          );
        },
      ),
    );

    if (result != null && mounted) {
      _onParamsChanged(result.applyTo(ref.read(currentParamsNotifierProvider)));
      _snack(
        tr("aiColorSuggestionApplied", args: [result.mood]),
        floating: true,
        seconds: 2,
      );
    }
  }

  // Export
  Future<void> _showExportDialog() async {
    final program = ref.read(shaderProgramProvider).value;
    if (program == null) return;

    final tasks = ref.read(exportTasksProvider);
    if (tasks.isEmpty) {
      _snack(tr('noShotsSelected'));
      return;
    }

    ExportFormat format = ExportFormat.png;
    int quality = 95;
    final isBatch = tasks.length > 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            isBatch
                ? '${tr('exportBatch')}  ·  ${tasks.length}'
                : tr('exportImage'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('format'), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SegmentedButton<ExportFormat>(
                segments: const [
                  ButtonSegment(value: ExportFormat.png, label: Text('PNG')),
                  ButtonSegment(value: ExportFormat.jpeg, label: Text('JPEG')),
                ],
                selected: {format},
                onSelectionChanged: (s) => setS(() => format = s.first),
              ),
              if (format == ExportFormat.jpeg) ...[
                const SizedBox(height: 14),
                Text(
                  '${tr('quality')}: $quality',
                  style: const TextStyle(fontSize: 12),
                ),
                Slider(
                  value: quality.toDouble(),
                  min: 50,
                  max: 100,
                  onChanged: (v) => setS(() => quality = v.round()),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                tr('exportDescription'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('export')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: tr('saveTo'),
    );
    if (folder == null) return;
    await _runExport(folder, format, quality, tasks);
  }

  Future<void> _runExport(
    String folder,
    ExportFormat fmt,
    int quality,
    List<ExportTask> tasks,
  ) async {
    final program = ref.read(shaderProgramProvider).value;
    if (program == null) return;
    final lut = ref.read(lutNotifierProvider);

    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((
      0,
      tr('progressNotifier'),
    ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: ValueListenableBuilder(
          valueListenable: progressNotifier,
          builder: (ctx, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value.$1),
              const SizedBox(height: 12),
              Text(value.$2, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    final stopwatch = Stopwatch()..start();
    String? lastOutPath;
    int doneCount = 0;

    try {
      for (int i = 0; i < tasks.length; i++) {
        final task = tasks[i];
        final outName = task.filename.replaceAll(
          RegExp(r'\.[^.]+$'),
          '_edited.${fmt.extension}',
        );
        final outPath = p.join(folder, outName);
        lastOutPath = outPath;

        final baseFrac = i / tasks.length;
        final span = 1 / tasks.length;

        await Exporter.exportFullRes(
          inputRawPath: task.path,
          outputPath: outPath,
          format: fmt,
          shaderProgram: program,
          params: task.params,
          lutTexture: lut.texture,
          lutSize: lut.size,
          jpegQuality: quality,
          onProgress: (f, s) {
            if (tasks.length == 1) {
              progressNotifier.value = (f, s);
            } else {
              progressNotifier.value = (
                baseFrac + f * span,
                tr(
                  'exportBatchProgress',
                  args: ['${i + 1}', '${tasks.length}', s],
                ),
              );
            }
          },
        );
        doneCount = i + 1;
      }
      stopwatch.stop();
      if (mounted) Navigator.pop(context);

      if (tasks.length == 1) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${tr('exportCompleted')} · ${stopwatch.elapsed.inSeconds}s · $lastOutPath',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'exportBatchCompleted',
                args: ['${tasks.length}', '${stopwatch.elapsed.inSeconds}'],
              ),
            ),
            action: SnackBarAction(label: tr('exportBatch'), onPressed: () {}),
            duration: const Duration(seconds: 5),
          ),
        );
        // 退出多选
        ref.read(exportSelectionNotifierProvider.notifier).toggleMode();
      }
    } catch (e, st) {
      if (mounted) Navigator.pop(context);
      debugPrint('Export error: $e\n$st');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tasks.length == 1
                ? '${tr('exportFailed')}: $e'
                : '${tr('exportFailed')} ($doneCount / ${tasks.length}): $e',
          ),
        ),
      );
    } finally {
      progressNotifier.dispose();
    }
  }

  void _snack(String msg, {bool floating = false, int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: floating ? SnackBarBehavior.floating : SnackBarBehavior.fixed,
        duration: Duration(seconds: seconds),
      ),
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    // 监听相机错误一次性 snackbar
    ref.listen(cameraNotifierProvider, (prev, next) {
      if (next.lastError != null && prev?.lastError != next.lastError) {
        _snack(tr('cameraError', args: [next.lastError!]));
      }
    });

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final ctrl =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;

        // Ctrl+Z / Ctrl+Shift+Z
        if (event is KeyDownEvent &&
            ctrl &&
            event.logicalKey == LogicalKeyboardKey.keyZ) {
          final shift = HardwareKeyboard.instance.isShiftPressed;
          final n = ref.read(historyNotifierProvider.notifier);
          if (shift) {
            n.redo();
          } else {
            n.undo();
          }
          return KeyEventResult.handled;
        }

        // \ 键 hold-to-compare
        if (event.logicalKey == LogicalKeyboardKey.backslash) {
          if (event is KeyDownEvent) {
            ref.read(compareBypassProvider.notifier).state = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            ref.read(compareBypassProvider.notifier).state = false;
            return KeyEventResult.handled;
          }
        }

        // Crop R/Esc/Enter
        if (event is KeyDownEvent) {
          final inCrop = ref.read(cropEditModeProvider);

          if (event.logicalKey == LogicalKeyboardKey.keyR && !inCrop) {
            enterCropMode(ref);
            return KeyEventResult.handled;
          }
          if (inCrop && event.logicalKey == LogicalKeyboardKey.escape) {
            cancelCrop(ref);
            return KeyEventResult.handled;
          }
          if (inCrop && event.logicalKey == LogicalKeyboardKey.enter) {
            commitCrop(ref);
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: SafeArea(
          child: isPhone ? _buildPhoneLayout() : _buildDesktopLayout(),
        ),
      ),
    );
  }

  Widget _buildPhoneLayout() {
    final session = ref.watch(tetherSessionNotifierProvider);
    final shots = ref.watch(shotsNotifierProvider);
    final activeShot = ref.watch(activeShotProvider);
    final selection = ref.watch(exportSelectionNotifierProvider);
    final preserve = ref.watch(preserveParamsProvider);
    final image = ref.watch(imageNotifierProvider).value;
    final program = ref.watch(shaderProgramProvider).value;
    final cameraState = ref.watch(cameraNotifierProvider);
    final hasImage = image != null && program != null;

    return Column(
      children: [
        _buildTopBar(),
        if (session != null)
          _buildTetherStatusBar(session, shots.length, preserve, cameraState),
        const _AIBanner(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Stack(
                children: [
                  const Positioned.fill(child: _PreviewArea()),
                  if (hasImage)
                    Positioned(
                      left: _histogramPosition.dx,
                      top: _histogramPosition.dy,
                      width: _miniHistogramW,
                      height: _miniHistogramH,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _histogramPosition = Offset(
                              (_histogramPosition.dx + details.delta.dx).clamp(
                                0.0,
                                previewSize.width - _miniHistogramW,
                              ),
                              (_histogramPosition.dy + details.delta.dy).clamp(
                                0.0,
                                previewSize.height - _miniHistogramH,
                              ),
                            );
                          });
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Opacity(
                            opacity: 0.9,
                            child: _buildHistogram(program, image),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (session != null && shots.isNotEmpty)
          TetherThumbStrip(
            shots: shots,
            activeShot: activeShot,
            onSelect: _onThumbTap,
            multiSelectMode: selection.multiSelectMode,
            selectedShots: shots
                .where((s) => selection.selectedPaths.contains(s.path))
                .toList(),
          ),
        _buildPhoneInfoBar(),
        if (hasImage) _buildPhoneToolPanel(),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    final session = ref.watch(tetherSessionNotifierProvider);
    final shots = ref.watch(shotsNotifierProvider);
    final activeShot = ref.watch(activeShotProvider);
    final selection = ref.watch(exportSelectionNotifierProvider);
    final preserve = ref.watch(preserveParamsProvider);
    final image = ref.watch(imageNotifierProvider).value;
    final program = ref.watch(shaderProgramProvider).value;
    final params = ref.watch(currentParamsNotifierProvider);
    final lut = ref.watch(lutNotifierProvider);
    final cameraState = ref.watch(cameraNotifierProvider);

    return Column(
      children: [
        _buildTopBar(),
        if (session != null)
          _buildTetherStatusBar(session, shots.length, preserve, cameraState),
        const _AIBanner(),
        Expanded(
          child: Row(
            children: [
              const Expanded(child: _PreviewArea()),
              if (image != null)
                AdjustmentPanel(
                  params: params,
                  onChanged: _onParamsChanged,
                  lutName: lut.name,
                  library:
                      ref.watch(lutLibraryNotifierProvider).value ?? const [],
                  onSelectLut: (entry) async {
                    if (entry == null) {
                      ref.read(lutNotifierProvider.notifier).clear();
                    } else {
                      await ref
                          .read(lutNotifierProvider.notifier)
                          .loadFromCubeFile(entry.filePath);
                    }
                  },
                  onImportLut: () async {
                    final entry = await ref
                        .read(lutLibraryNotifierProvider.notifier)
                        .importFromFile();
                    if (entry != null) {
                      await ref
                          .read(lutNotifierProvider.notifier)
                          .loadFromCubeFile(entry.filePath);
                    }
                  },
                  onDeleteLut: (entry) async {
                    final cur = ref.read(lutNotifierProvider);
                    if (cur.name == '${entry.name}.cube') {
                      ref.read(lutNotifierProvider.notifier).clear();
                    }
                    await ref
                        .read(lutLibraryNotifierProvider.notifier)
                        .delete(entry);
                  },
                  histogram: program == null
                      ? null
                      : _buildHistogram(program, image),
                  presetBar: const PresetBar(),
                ),
            ],
          ),
        ),
        if (session != null && shots.isNotEmpty)
          TetherThumbStrip(
            shots: shots,
            activeShot: activeShot,
            onSelect: _onThumbTap,
            multiSelectMode: selection.multiSelectMode,
            selectedShots: shots
                .where((s) => selection.selectedPaths.contains(s.path))
                .toList(),
          ),
        _buildBottomPanel(),
      ],
    );
  }

  Widget _buildTetherStatusBar(
    TetherSession session,
    int shotCount,
    bool preserve,
    CameraState cameraState,
  ) {
    ref.watch(tickerProvider);
    return TetherStatusBar(
      watchPath: cameraState.modelName != null
          ? '${cameraState.modelName} → ${session.watchPath}'
          : session.watchPath,
      shotCount: shotCount,
      lastShotAt: session.lastShotAt,
      onStop: _stopAllTether,
      preserveParams: preserve,
      onPreserveChanged: _togglePreserve,
    );
  }

  Widget _buildHistogram(ui.FragmentProgram program, DecodedImageState image) {
    final params = ref.watch(effectiveParamsProvider);
    final lut = ref.watch(lutNotifierProvider);
    final lutEnabled = ref.watch(effectiveLutEnabledProvider);
    return LiveHistogramPanel(
      program: program,
      sourceImage: image.uiImage,
      params: params,
      lutTexture: lutEnabled ? lut.texture : null,
      lutSize: lutEnabled ? lut.size : 0,
      crop: params.crop,
    );
  }

  Widget _buildTopBar() {
    final image = ref.watch(imageNotifierProvider).value;
    final program = ref.watch(shaderProgramProvider).value;
    final session = ref.watch(tetherSessionNotifierProvider);
    final cameraState = ref.watch(cameraNotifierProvider);
    final selection = ref.watch(exportSelectionNotifierProvider);
    final shots = ref.watch(shotsNotifierProvider);
    final hist = ref.watch(historyNotifierProvider);
    final notifier = ref.read(historyNotifierProvider.notifier);

    final hasImage = image != null && program != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          if (hasImage) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: tr('undo'),
              onPressed: hist.canUndo ? notifier.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: tr('redo'),
              onPressed: hist.canRedo ? notifier.redo : null,
            ),
            const VerticalDivider(width: 1),
            IconButton(
              icon: const Icon(Icons.crop),
              tooltip: tr('crop'),
              onPressed: hasImage ? () => enterCropMode(ref) : null,
            ),
            const CompareButton(),
            IconButton(
              icon: const Icon(
                Icons.auto_awesome,
                size: 18,
                color: Color(0xFF6B5BFF),
              ),
              tooltip: tr("aiColorSuggestionHint"),
              onPressed: _showAISuggestion,
              onLongPress: _showAISettings,
            ),
          ],
          if (session == null)
            IconButton(
              icon: const Icon(Icons.cable_rounded, size: 18),
              tooltip: tr("tetherFolderMonitor"),
              onPressed: _startFolderTether,
            ),
          if (!cameraState.isActive && session == null)
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              tooltip: tr("tetherCamera"),
              onPressed: _startCameraTether,
            )
          else if (cameraState.isActive)
            IconButton(
              icon: Icon(
                Icons.photo_camera,
                size: 18,
                color: cameraState.shutterFlash
                    ? Colors.greenAccent
                    : Colors.greenAccent.withValues(alpha: 0.85),
              ),
              tooltip: tr(
                "cameraConnected",
                args: [cameraState.modelName ?? tr("cameraModelUnknown")],
              ),
              onPressed: _stopAllTether,
            ),
          const SizedBox(width: 4),
          if (hasImage)
            IconButton(
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              tooltip: tr("export"),
              onPressed: _showExportDialog,
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              selection.multiSelectMode
                  ? Icons.checklist_rtl_rounded
                  : Icons.checklist_rounded,
              size: 18,
            ),
            color: selection.multiSelectMode
                ? const Color(0xFF6B5BFF)
                : Colors.white.withValues(alpha: 0.85),
            tooltip: selection.multiSelectMode
                ? tr('multiSelectExit')
                : tr('multiSelect'),
            onPressed: shots.isEmpty
                ? null
                : () => ref
                      .read(exportSelectionNotifierProvider.notifier)
                      .toggleMode(),
          ),
          if (selection.multiSelectMode) ...[
            if (selection.selectedPaths.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B5BFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tr(
                    'selectedShots',
                    args: ['${selection.selectedPaths.length}'],
                  ),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B5BFF),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                final notifier = ref.read(
                  exportSelectionNotifierProvider.notifier,
                );
                if (selection.selectedPaths.length == shots.length) {
                  notifier.clearSelection();
                } else {
                  notifier.selectAll(shots.map((s) => s.path));
                }
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: Text(
                selection.selectedPaths.length == shots.length
                    ? tr('selectNone')
                    : tr('selectAll'),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneInfoBar() {
    final image = ref.watch(imageNotifierProvider).value;
    final path = ref.watch(activeFilePathProvider);
    final m = image?.decoded.metadata;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              m == null
                  ? (path ?? tr('imageNotChosen'))
                  : '${m.cameraModel} · ISO ${m.iso} · ${m.shutterDisplay} · f/${m.aperture.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (image != null)
            Row(
              children: [
                Text(
                  '${image.decoded.width}×${image.decoded.height}',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.greenAccent.withValues(alpha: 0.8),
                  ),
                ),
                if (image.isPreliminary) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.2,
                      color: Colors.amberAccent.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'HD…',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amberAccent.withValues(alpha: 0.7),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPhoneToolPanel() {
    final params = ref.watch(currentParamsNotifierProvider);
    final lut = ref.watch(lutNotifierProvider);
    final library = ref.watch(lutLibraryNotifierProvider).value ?? const [];

    return SizedBox(
      height: 320,
      child: DefaultTabController(
        length: 5,
        child: Container(
          color: const Color(0xFF14141A),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        labelPadding: EdgeInsets.zero,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: const TextStyle(fontSize: 11),
                        tabs: [
                          Tab(text: tr("light"), height: 36),
                          Tab(text: tr("color"), height: 36),
                          Tab(text: tr("hsl"), height: 36),
                          Tab(text: 'LUT', height: 36),
                          Tab(text: tr("preset"), height: 36),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: tr("reset"),
                      onPressed: () =>
                          _onParamsChanged(AdjustmentParams.neutral),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      child: LightSection(
                        params: params,
                        onChanged: _onParamsChanged,
                      ),
                    ),
                    SingleChildScrollView(
                      child: WhiteBalanceColorSection(
                        params: params,
                        onChanged: _onParamsChanged,
                      ),
                    ),
                    SingleChildScrollView(
                      child: HslSection(
                        bands: params.hsl,
                        onChanged: (b) =>
                            _onParamsChanged(params.copyWith(hsl: b)),
                      ),
                    ),
                    SingleChildScrollView(
                      child: LutSection(
                        lutName: lut.name,
                        intensity: params.lutIntensity,
                        onIntensityChanged: (v) =>
                            _onParamsChanged(params.copyWith(lutIntensity: v)),
                        library: library,
                        onSelect: (entry) async {
                          if (entry == null) {
                            ref.read(lutNotifierProvider.notifier).clear();
                          } else {
                            await ref
                                .read(lutNotifierProvider.notifier)
                                .loadFromCubeFile(entry.filePath);
                          }
                        },
                        onImport: () async {
                          final entry = await ref
                              .read(lutLibraryNotifierProvider.notifier)
                              .importFromFile();
                          if (entry != null) {
                            await ref
                                .read(lutNotifierProvider.notifier)
                                .loadFromCubeFile(entry.filePath);
                          }
                        },
                        onDelete: (entry) async {
                          final cur = ref.read(lutNotifierProvider);
                          if (cur.name == '${entry.name}.cube') {
                            ref.read(lutNotifierProvider.notifier).clear();
                          }
                          await ref
                              .read(lutLibraryNotifierProvider.notifier)
                              .delete(entry);
                        },
                      ),
                    ),
                    const PresetTabContent(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    final image = ref.watch(imageNotifierProvider).value;
    final isLoading = ref.watch(imageNotifierProvider).isLoading;
    final path = ref.watch(activeFilePathProvider);
    final m = image?.decoded.metadata;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path ?? tr('imageNotChosen'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  m == null ? '——' : m.toString(),
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (image != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${image.decoded.width} × ${image.decoded.height} · '
                        '${image.decoded.bitsPerChannel}-bit · '
                        'decode ${image.decodeTime.inMilliseconds}ms · '
                        'convert ${image.convertTime.inMilliseconds}ms',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.greenAccent.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (image.isPreliminary) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 9,
                          height: 9,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.2,
                            color: Colors.amberAccent.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'HD…',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.amberAccent.withValues(alpha: 0.7),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: isLoading ? null : _pickAndDecode,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(tr("imageChoose")),
          ),
        ],
      ),
    );
  }
}

// Preview area
class _PreviewArea extends ConsumerWidget {
  const _PreviewArea();

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
    if (cropMode) return _buildCropEdit(state, params, lut, lutEnabled);
    return _buildCroppedPreview(state, params, lut, lutEnabled);
  }

  Widget _buildCropEdit(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
  ) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final imgW = state.uiImage.width.toDouble();
        final imgH = state.uiImage.height.toDouble();
        final fit = applyBoxFit(
          BoxFit.contain,
          Size(imgW, imgH),
          constraints.biggest,
        );
        final displaySize = fit.destination;

        return Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.fromSize(
                size: displaySize,
                child: PreviewRenderer(
                  image: state.uiImage,
                  params: params,
                  lutTexture: lutEnabled ? lut.texture : null,
                  lutSize: lutEnabled ? lut.size : 0,
                ),
              ),
              SizedBox.fromSize(
                size: displaySize,
                child: CropOverlay(imageDisplaySize: displaySize),
              ),
              Positioned(bottom: 16, child: CropPanel()),
            ],
          ),
        );
      },
    );
  }

  /// 普通模式：显示已裁剪的画面（OverflowBox + Transform 模拟裁剪）
  Widget _buildCroppedPreview(
    DecodedImageState state,
    AdjustmentParams params,
    LutState lut,
    bool lutEnabled,
  ) {
    final crop = params.crop;
    final image = state.uiImage;

    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final imgW = image.width.toDouble();
          final imgH = image.height.toDouble();
          final outAspect = (imgW * crop.width) / (imgH * crop.height);
          final box = applyBoxFit(
            BoxFit.contain,
            Size(outAspect, 1.0),
            constraints.biggest,
          ).destination;

          final fullW = box.width / crop.width;
          final fullH = box.height / crop.height;
          final tx = -crop.x * fullW;
          final ty = -crop.y * fullH;

          return Center(
            child: SizedBox.fromSize(
              size: box,
              child: ClipRect(
                child: OverflowBox(
                  minWidth: fullW,
                  maxWidth: fullW,
                  minHeight: fullH,
                  maxHeight: fullH,
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: Offset(tx, ty),
                    child: SizedBox(
                      width: fullW,
                      height: fullH,
                      child: PreviewRenderer(
                        image: image,
                        params: params,
                        lutTexture: lutEnabled ? lut.texture : null,
                        lutSize: lutEnabled ? lut.size : 0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
              final result = await FilePicker.platform.pickFiles();
              if (result == null || result.files.isEmpty) return;
              final path = result.files.single.path;
              if (path != null) {
                ref.read(activeFilePathProvider.notifier).set(path);
              }
            },
            icon: const Icon(Icons.folder_open),
            label: Text(tr("imageChoose")),
          ),
          const SizedBox(height: 8),
          Text(
            'ARW · CR2 · CR3 · NEF · RAF · DNG · ORF · RW2 …',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// AI Banner
class _AIBanner extends ConsumerWidget {
  const _AIBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiAutoNotifierProvider);

    if (ai.inProgress && ai.pendingSuggestion == null) {
      return Container(
        color: const Color(0xFF6B5BFF).withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF6B5BFF),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              tr("aiColorInProgress"),
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }
    if (ai.pendingSuggestion == null) return const SizedBox.shrink();

    final s = ai.pendingSuggestion!;
    return Material(
      color: const Color(0xFF6B5BFF).withValues(alpha: 0.15),
      child: InkWell(
        onTap: () {
          ref.read(aiAutoNotifierProvider.notifier).applyPending();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: Color(0xFF6B5BFF),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: tr("aiColorSuggestionLabel"),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: s.mood.isNotEmpty
                            ? s.mood
                            : tr("aiColorSuggestionReady"),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(aiAutoNotifierProvider.notifier).applyPending(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(tr("apply"), style: const TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(aiAutoNotifierProvider.notifier).dismissPending(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  tr("ignore"),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          ],
        ),
      ),
    );
  }
}
