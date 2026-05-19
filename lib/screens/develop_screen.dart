import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import '../services/app_settings.dart';
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
import '../widgets/local_mask_overlay.dart';
import '../widgets/local_panel.dart';
import '../widgets/multi_pass_preview.dart';
import '../widgets/preset_bar.dart';
import '../widgets/tether_widgets.dart';
import '../state/app_settings_state.dart';
import 'settings_screen.dart';

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
    // 默认文件夹
    String? folder = ref.read(tetherFolderProvider);
    folder ??= await AppSettings.getTetherFolder();

    if (folder != null) {
      final exists = await Directory(folder).exists();
      if (!exists) {
        // 文件夹不存在
        await ref.read(tetherFolderProvider.notifier).clear();
        folder = null;
      }
    }

    // 无默认文件夹
    if (folder == null) {
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: tr('tetherFolderChoose'),
      );
      if (picked == null || picked.isEmpty) return;

      if (!mounted) return;
      final remember = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr("settingsRememberFolder")),
          content: Text(
            '${tr("settingsRememberAsDefaultDesc")}\n\n$picked',
            style: const TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr("settingsRememberOnlyOnce")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr("settingsRememberSave")),
            ),
          ],
        ),
      );

      if (remember == true) {
        await ref.read(tetherFolderProvider.notifier).set(picked);
      }
      folder = picked;
    }

    // 真正启动
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
    final maskProgram = ref.read(maskShaderProgramProvider).value;
    final image = ref.read(imageNotifierProvider).value;
    if (program == null || image == null || maskProgram == null) return;

    final result = await showDialog<AIColorSuggestion>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AISuggestionDialog(
        currentParams: ref.read(currentParamsNotifierProvider),
        renderPreviewToFile: () async {
          final lut = ref.read(lutNotifierProvider);
          return AIInputRenderer.renderToTempFile(
            program: program,
            maskProgram: maskProgram,
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

        final maskProgram = ref.read(maskShaderProgramProvider).value;
        if (maskProgram == null) {
          _snack('Mask shader loading...');
          return;
        }

        await Exporter.exportFullRes(
          inputRawPath: task.path,
          outputPath: outPath,
          format: fmt,
          shaderProgram: program,
          maskProgram: maskProgram,
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
    final isVertical = MediaQuery.of(context).size.shortestSide < 600;
    final isFullscreen = ref.watch(fullscreenPreviewProvider);
    ref.listen(cameraNotifierProvider, (prev, next) {
      if (next.lastError != null && prev?.lastError != next.lastError) {
        _snack(tr('cameraError', args: [next.lastError!]));
      }
    });

    if (isFullscreen) {
      return _buildFullscreen();
    }

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

        // F11
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.f11) {
          final cur = ref.read(fullscreenPreviewProvider);
          ref.read(fullscreenPreviewProvider.notifier).state = !cur;
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
          child: isVertical ? _buildVerticalLayout() : _buildHorizontalLayout(),
        ),
      ),
    );
  }

  Widget _buildFullscreen() {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          ref.read(fullscreenPreviewProvider.notifier).state = false;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTap: () =>
                    ref.read(fullscreenPreviewProvider.notifier).state = false,
                child: const _PreviewArea(),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: _FullscreenExitButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalLayout() {
    final session = ref.watch(tetherSessionNotifierProvider);
    final shots = ref.watch(shotsNotifierProvider);
    final activeShot = ref.watch(activeShotProvider);
    final selection = ref.watch(exportSelectionNotifierProvider);
    final preserve = ref.watch(preserveParamsProvider);
    final image = ref.watch(imageNotifierProvider).value;
    final program = ref.watch(shaderProgramProvider).value;
    final cameraState = ref.watch(cameraNotifierProvider);
    final cropEditMode = ref.watch(cropEditModeProvider);
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
        if (session != null && shots.isNotEmpty && !cropEditMode)
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

  Widget _buildHorizontalLayout() {
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
    final mask = ref.watch(maskShaderProgramProvider).value;
    if (mask == null) return const SizedBox.shrink();
    final params = ref.watch(effectiveParamsProvider);
    final lut = ref.watch(lutNotifierProvider);
    final lutEnabled = ref.watch(effectiveLutEnabledProvider);
    return LiveHistogramPanel(
      program: program,
      maskProgram: mask,
      sourceImage: image.uiImage,
      params: params,
      lutTexture: lutEnabled ? lut.texture : null,
      lutSize: lutEnabled ? lut.size : 0,
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
    final isVertical = MediaQuery.of(context).size.shortestSide < 600;

    // 紧凑模式
    Widget compactIcon({
      required IconData icon,
      required String tooltip,
      VoidCallback? onPressed,
      VoidCallback? onLongPress,
      Color? color,
      double size = 20,
    }) {
      final button = IconButton(
        icon: Icon(icon, size: isVertical ? 18 : size, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: isVertical
            ? VisualDensity.compact
            : VisualDensity.standard,
        padding: isVertical ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
        constraints: isVertical
            ? const BoxConstraints(minWidth: 32, minHeight: 32)
            : const BoxConstraints(minWidth: 40, minHeight: 40),
      );
      if (onLongPress == null) return button;
      return GestureDetector(onLongPress: onLongPress, child: button);
    }

    // 折到溢出菜单
    final overflowItems = <PopupMenuEntry<String>>[];
    if (hasImage) {
      overflowItems.add(
        PopupMenuItem(
          value: 'ai',
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 18,
                color: Color(0xFF6B5BFF),
              ),
              const SizedBox(width: 12),
              Text(tr('aiColorSuggestion')),
            ],
          ),
        ),
      );
    }
    if (!cameraState.isActive && session == null) {
      overflowItems.add(
        PopupMenuItem(
          value: 'tether_camera',
          child: Row(
            children: [
              const Icon(Icons.photo_camera_outlined, size: 18),
              const SizedBox(width: 12),
              Text(tr('tetherCamera')),
            ],
          ),
        ),
      );
    }
    if (session == null) {
      overflowItems.add(
        PopupMenuItem(
          value: 'tether_folder',
          child: Row(
            children: [
              const Icon(Icons.cable_rounded, size: 18),
              const SizedBox(width: 12),
              Text(tr('tetherFolderMonitor')),
            ],
          ),
        ),
      );
    }
    if (hasImage) {
      overflowItems.add(
        PopupMenuItem(
          value: 'fullscreen',
          child: Row(
            children: [
              Icon(Icons.fullscreen, size: 18),
              SizedBox(width: 12),
              Text(tr("fullscreenPreview")),
            ],
          ),
        ),
      );
    }
    overflowItems.add(
      PopupMenuItem(
        value: 'settings',
        child: Row(
          children: [
            const Icon(Icons.settings_outlined, size: 18),
            const SizedBox(width: 12),
            Text(tr("settings")),
          ],
        ),
      ),
    );

    void handleMenu(String key) {
      switch (key) {
        case 'ai':
          _showAISuggestion();
          break;
        case 'tether_folder':
          _startFolderTether();
          break;
        case 'tether_camera':
          _startCameraTether();
          break;
        case 'fullscreen':
          ref.read(fullscreenPreviewProvider.notifier).state = true;
          break;
        case 'settings':
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
          break;
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isVertical ? 8 : 24,
        vertical: isVertical ? 6 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          if (hasImage) ...[
            compactIcon(
              icon: Icons.undo,
              tooltip: tr('undo'),
              onPressed: hist.canUndo ? notifier.undo : null,
            ),
            compactIcon(
              icon: Icons.redo,
              tooltip: tr('redo'),
              onPressed: hist.canRedo ? notifier.redo : null,
            ),
            if (!isVertical) const VerticalDivider(width: 1),
            compactIcon(
              icon: Icons.crop,
              tooltip: tr('crop'),
              onPressed: () => enterCropMode(ref),
            ),
            const CompareButton(),
          ],
          // 相机活动状态始终显示
          if (cameraState.isActive)
            compactIcon(
              icon: Icons.photo_camera,
              color: cameraState.shutterFlash
                  ? Colors.greenAccent
                  : Colors.greenAccent.withValues(alpha: 0.85),
              tooltip: tr(
                "cameraConnected",
                args: [cameraState.modelName ?? tr("cameraModelUnknown")],
              ),
              onPressed: _stopAllTether,
            ),
          if (hasImage) ...[
            compactIcon(
              icon: Icons.ios_share_rounded,
              tooltip: tr("export"),
              onPressed: _showExportDialog,
            ),
            compactIcon(
              icon: selection.multiSelectMode
                  ? Icons.checklist_rtl_rounded
                  : Icons.checklist_rounded,
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
          ],
          // 水平直接展示，垂直布局折到菜单
          if (!isVertical) ...[
            if (session == null)
              compactIcon(
                icon: Icons.cable_rounded,
                tooltip: tr("tetherFolderMonitor"),
                onPressed: _startFolderTether,
              ),
            if (!cameraState.isActive && session == null)
              compactIcon(
                icon: Icons.photo_camera_outlined,
                tooltip: tr("tetherCamera"),
                onPressed: _startCameraTether,
              ),
            if (hasImage) ...[
              compactIcon(
                icon: Icons.auto_awesome,
                color: const Color(0xFF6B5BFF),
                tooltip: tr("aiColorSuggestionHint"),
                onPressed: _showAISuggestion,
                onLongPress: _showAISettings,
              ),
              compactIcon(
                icon: Icons.fullscreen,
                tooltip: tr("fullscreenPreviewBtnHint"),
                onPressed: () =>
                    ref.read(fullscreenPreviewProvider.notifier).state = true,
              ),
            ],
            compactIcon(
              icon: Icons.settings_outlined,
              tooltip: tr("settings"),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
          // 垂直布局"更多"按钮
          if (isVertical && overflowItems.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              itemBuilder: (_) => overflowItems,
              onSelected: handleMenu,
            ),
          // 多选信息条
          if (selection.multiSelectMode) ...[
            if (selection.selectedPaths.isNotEmpty)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            TextButton(
              onPressed: () {
                final n = ref.read(exportSelectionNotifierProvider.notifier);
                if (selection.selectedPaths.length == shots.length) {
                  n.clearSelection();
                } else {
                  n.selectAll(shots.map((s) => s.path));
                }
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
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
        length: 6,
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
                          Tab(text: tr("local"), height: 36),
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
                    const SingleChildScrollView(child: LocalPanel()),
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

class _FullscreenExitButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => ref.read(fullscreenPreviewProvider.notifier).state = false,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.fullscreen_exit, size: 22, color: Colors.white),
        ),
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

                // oriented 后的尺寸
                final orientedW = draft.orientationSwapsAxes ? imgH : imgW;
                final orientedH = draft.orientationSwapsAxes ? imgW : imgH;
                final fit = applyBoxFit(
                  BoxFit.contain,
                  Size(orientedW, orientedH),
                  constraints.biggest,
                );
                final displaySize = fit.destination;

                // Transform: 把"未变换的源"画到 oriented 视图里
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
                                lutTexture: lutEnabled ? lut.texture : null,
                                lutSize: lutEnabled ? lut.size : 0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Overlay 画在 oriented 后的画布上
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
    final selectedLocalId = ref.watch(selectedLocalIdProvider);

    Widget wrapOverlay(Widget content, Size displaySize) {
      if (selectedLocalId == null) return content;
      return Stack(
        children: [
          content,
          Positioned.fill(
            child: LocalMaskOverlay(imageDisplaySize: displaySize),
          ),
        ],
      );
    }

    // 带有local
    if (hasLocals) {
      final maskProgram = ref.watch(maskShaderProgramProvider).value;
      final develop = ref.watch(shaderProgramProvider).value;
      if (develop == null || maskProgram == null) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return LayoutBuilder(
        builder: (ctx, constraints) {
          final imgW = state.uiImage.width.toDouble();
          final imgH = state.uiImage.height.toDouble();
          final outAspect = params.crop.outAspectFor(imgW, imgH);
          final isVertical = MediaQuery.of(ctx).size.shortestSide < 600;
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
                    lutTexture: lutEnabled ? lut.texture : null,
                    lutSize: lutEnabled ? lut.size : 0,
                    idleMaxEdge: isVertical ? 1600 : 2400,
                    draggingMaxEdge: isVertical ? 600 : 800,
                  ),
                  box,
                ),
              ),
            ),
          );
        },
      );
    }

    // 无local
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
                      lutTexture: lutEnabled ? lut.texture : null,
                      lutSize: lutEnabled ? lut.size : 0,
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

          // orientation 后的尺寸
          final orientedW = crop.orientationSwapsAxes ? imgH : imgW;
          final orientedH = crop.orientationSwapsAxes ? imgW : imgH;

          // 让crop rect 区域刚好等于 box
          // box.width = orientedW * crop.width * scale → scale = box.width / (orientedW * crop.width)
          final scale = box.width / (orientedW * crop.width);
          final renderedFullW = imgW * scale;
          final renderedFullH = imgH * scale;
          final renderedOrientedW = orientedW * scale;
          final renderedOrientedH = orientedH * scale;

          // Transform 矩阵
          // 1) 移动到 box 的中心
          // 2) 旋转 90°×orientation + straighten
          // 3) flip
          // 4) 平移回到 oriented 坐标的中心
          // 5) 减去 crop 偏移
          final matrix = Matrix4.identity()
            ..translate(box.width / 2, box.height / 2, 0)
            ..rotateZ(
              crop.orientation * math.pi / 2 + crop.straighten * math.pi / 180,
            )
            ..scale(crop.flipH ? -1.0 : 1.0, crop.flipV ? -1.0 : 1.0)
            // 此时坐标系原点在 box 中心，方向跟 oriented 一致
            // 把 oriented 图像放在它的 (crop.x..crop.x+crop.width) 的中心
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
                          lutTexture: lutEnabled ? lut.texture : null,
                          lutSize: lutEnabled ? lut.size : 0,
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
