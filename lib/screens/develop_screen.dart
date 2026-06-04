import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/keybindings/app_action.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/export_config.dart';
import '../core/models/export_job.dart';
import '../core/models/sync_options.dart';
import '../core/models/tethered_shot.dart';
import '../native/raw_bridge.dart';
import '../services/ai/ai_color_service.dart';
import '../services/ai/ai_input_renderer.dart';
import '../services/ai/ai_settings.dart';
import '../services/app_settings.dart';
import '../services/update_service.dart';
import '../state/providers.dart';
import '../widgets/adjustment_panel.dart';
import '../widgets/ai_settings_dialog.dart';
import '../widgets/ai_suggestion_dialog.dart';
import '../widgets/camera_picker_dialog.dart';
import '../widgets/develop_misc_widgets.dart';
import '../widgets/develop_sections.dart';
import '../widgets/develop_top_bar.dart';
import '../widgets/export_dialog.dart';
import '../widgets/preview_area.dart';
import 'folder_import_screen.dart';
import '../widgets/histogram_panel.dart';
import '../widgets/local_panel.dart';
import '../widgets/preset_bar.dart';
import '../widgets/tether_widgets.dart';
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
  bool _immersiveOn = false;
  static const _miniHistogramW = 140.0;
  static const _miniHistogramH = 70.0;

  @override
  void initState() {
    super.initState();
    _libRawVersion = tr('loading');
    _probeFfi();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentUpdateCheck());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _silentUpdateCheck() async {
    try {
      final info = await UpdateService.check();
      if (info == null || !info.hasUpdate || !mounted) return;
      final ignored = await UpdateService.ignoredVersion();
      if (ignored == info.latestVersion) return;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => UpdateDialog(info: info, showIgnore: true),
      );
    } catch (_) {}
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

  Future<void> _startFolderTether() async {
    String? folder = ref.read(tetherFolderProvider);
    folder ??= await AppSettings.getTetherFolder();

    if (folder != null) {
      final exists = await Directory(folder).exists();
      if (!exists) {
        await ref.read(tetherFolderProvider.notifier).clear();
        folder = null;
      }
    }

    if (folder == null) {
      final picked = await FilePicker.getDirectoryPath(
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
            lutTexture: lut.textureA,
            lutSize: lut.sizeA,
            lutTextureB: lut.textureB,
            lutSizeB: lut.sizeB,
            curveTexture: ref.watch(effectiveCurveTextureProvider),
            sharpenProgram: ref.read(sharpenShaderProgramProvider).value,
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

  // Export：弹配置对话框 → 选目录 → 组装 jobs → 入队
  Future<void> _showExportDialog() async {
    final program = ref.read(shaderProgramProvider).value;
    if (program == null) return;

    final tasks = ref.read(exportTasksProvider);
    if (tasks.isEmpty) {
      _snack(tr('noShotsSelected'));
      return;
    }

    final result = await showExportDialog(
      context,
      tasks: tasks,
      initialQuality: ref.read(exportQualityProvider),
      initialTemplate: ref.read(exportTemplateProvider),
    );
    if (result == null) return;

    // 记住模板
    ref.read(exportTemplateProvider.notifier).set(result.filenameTemplate);

    if (!mounted) return;
    final folder = await FilePicker.getDirectoryPath(dialogTitle: tr('saveTo'));
    if (folder == null) return;

    // 快照当前全局 LUT
    final config = ExportConfig(
      format: result.format,
      jpegQuality: result.jpegQuality,
      filenameTemplate: result.filenameTemplate,
      outputDir: folder,
      writeExif: result.writeExif,
      denoiseEngine: result.denoiseEngine,
      denoiseParallelism: ref.read(denoiseParallelismProvider),
    );

    // 组装 jobs
    final baseId = DateTime.now().microsecondsSinceEpoch;
    final jobs = <ExportJob>[
      for (int i = 0; i < tasks.length; i++)
        ExportJob(
          id: '${baseId}_$i',
          inputPath: tasks[i].path,
          displayName: p.basename(tasks[i].path),
          params: tasks[i].params,
          config: config,
          seq: i + 1,
        ),
    ];

    ref.read(exportQueueProvider.notifier).enqueue(jobs);

    // 退出多选（若批量）
    if (tasks.length > 1) {
      ref.read(exportSelectionNotifierProvider.notifier).toggleMode();
    }

    _snack(
      tr('exportQueued', args: ['${jobs.length}']),
      floating: true,
      seconds: 2,
    );
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
    final isVertical =
        MediaQuery.of(context).size.width < 600 &&
        MediaQuery.of(context).orientation == Orientation.portrait;
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (landscape != _immersiveOn) {
      _immersiveOn = landscape;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SystemChrome.setEnabledSystemUIMode(
          landscape
              ? SystemUiMode
                    .immersiveSticky // 横屏：隐藏状态/导航栏，下拉临时显示后自动收起
              : SystemUiMode.edgeToEdge, // 竖屏：正常显示
        );
      });
    }
    final isFullscreen = ref.watch(fullscreenPreviewProvider);
    final keys = ref.watch(keybindingServiceProvider);
    // 持久化
    ref.listen(currentParamsNotifierProvider, (prev, next) {
      if (!ref.read(sidecarEnabledProvider)) return;
      final activePath = ref.read(activeShotPathProvider);
      if (activePath == null) return;
      final active = ref.read(activeShotProvider);
      ref
          .read(sidecarWriterProvider)
          .schedule(
            activePath,
            next, // 最新参数
            active?.rating ?? 0,
            active?.flag ?? ShotFlag.none,
          );
    });
    // 监听过滤条件变化
    ref.listen(filteredShotsProvider, (prev, next) {
      final active = ref.read(activeShotPathProvider);
      if (next.isEmpty) return;
      if (active == null || !next.any((s) => s.path == active)) {
        final first = next.first;
        ref.read(activeShotPathProvider.notifier).set(first.path);
        ref.read(activeFilePathProvider.notifier).set(first.path);
      }
    });
    // 监听曲线变化
    ref.listen(currentParamsNotifierProvider.select((p) => p.curves), (
      prev,
      next,
    ) {
      ref.read(curveTextureProvider.notifier).update(next);
    });
    // 监听相机错误
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
      onKeyEvent: (node, event) => _handleKeyEvent(event, keys),
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
                child: const PreviewArea(),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: FullscreenExitButton(),
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
        DevelopTopBar(
          onExport: _showExportDialog,
          onSync: _syncToSelected,
          onTetherFolder: _startFolderTether,
          onTetherCamera: _startCameraTether,
          onStopTether: _stopAllTether,
          onAI: _showAISuggestion,
          onAILongPress: _showAISettings,
        ),
        if (session != null)
          _buildTetherStatusBar(session, shots.length, preserve, cameraState),
        const AIBanner(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Stack(
                children: [
                  const Positioned.fill(child: PreviewArea()),
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
        if (shots.isNotEmpty && !cropEditMode)
          TetherThumbStrip(
            shots: ref.watch(filteredShotsProvider),
            activeShot: activeShot,
            onSelect: _onThumbTap,
            multiSelectMode: selection.multiSelectMode,
            selectedShots: shots
                .where((s) => selection.selectedPaths.contains(s.path))
                .toList(),
          ),
        _buildVerticalInfoBar(),
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
    final cameraState = ref.watch(cameraNotifierProvider);
    final cropEditMode = ref.watch(cropEditModeProvider);

    return Column(
      children: [
        DevelopTopBar(
          onExport: _showExportDialog,
          onSync: _syncToSelected,
          onTetherFolder: _startFolderTether,
          onTetherCamera: _startCameraTether,
          onStopTether: _stopAllTether,
          onAI: _showAISuggestion,
          onAILongPress: _showAISettings,
        ),
        if (session != null)
          _buildTetherStatusBar(session, shots.length, preserve, cameraState),
        const AIBanner(),
        Expanded(
          child: Row(
            children: [
              if (shots.isNotEmpty && !cropEditMode)
                TetherThumbStrip(
                  shots: ref.watch(filteredShotsProvider),
                  activeShot: activeShot,
                  onSelect: _onThumbTap,
                  multiSelectMode: selection.multiSelectMode,
                  selectedShots: shots
                      .where((s) => selection.selectedPaths.contains(s.path))
                      .toList(),
                  axis: Axis.vertical,
                ),
              const Expanded(child: PreviewArea()),
              if (image != null)
                AdjustmentPanel(
                  params: params,
                  onChanged: _onParamsChanged,
                  histogram: program == null
                      ? null
                      : _buildHistogram(program, image),
                  presetBar: const PresetBar(),
                  info: _buildHorizontalInfoBar(),
                  onEnterCrop: () => enterCropMode(ref),
                ),
            ],
          ),
        ),
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
      lutTexture: lutEnabled ? lut.textureA : null,
      lutSize: lutEnabled ? lut.sizeA : 0,
      lutTextureB: lutEnabled ? lut.textureB : null,
      lutSizeB: lutEnabled ? lut.sizeB : 0,
      curveTexture: ref.watch(effectiveCurveTextureProvider),
    );
  }

  Widget _buildVerticalInfoBar() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m?.summary.isNotEmpty == true
                      ? m!.summary
                      : (path != null
                            ? p.basename(path)
                            : tr('imageNotChosen')),
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (image != null) ...[
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
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Platform.isAndroid
                        ? Icons.folder_copy_outlined
                        : Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  tooltip: Platform.isAndroid
                      ? tr("folderImport")
                      : tr("imageChoose"),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: _importImages,
                ),
              ],
            ],
          ),
          if (image != null) RatingFlagBar(),
        ],
      ),
    );
  }

  Widget _buildPhoneToolPanel() {
    final params = ref.watch(currentParamsNotifierProvider);

    return SizedBox(
      height: 320,
      child: DefaultTabController(
        length: 7,
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
                          Tab(text: tr('detail'), height: 36),
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
                    SingleChildScrollView(child: LutSection()),
                    SingleChildScrollView(
                      child: DetailSection(
                        params: params,
                        onChanged: _onParamsChanged,
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

  Widget _buildHorizontalInfoBar() {
    final image = ref.watch(imageNotifierProvider).value;
    final isLoading = ref.watch(imageNotifierProvider).isLoading;
    final path = ref.watch(activeFilePathProvider);
    final m = image?.decoded.metadata;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m?.summary.isNotEmpty == true
                ? m!.summary
                : (path != null ? p.basename(path) : tr('imageNotChosen')),
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (image != null) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${image.decoded.width}×${image.decoded.height} · '
                    '${image.decoded.bitsPerChannel}-bit · '
                    'decode ${image.decodeTime.inMilliseconds}ms · '
                    'convert ${image.convertTime.inMilliseconds}ms',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                      color: Colors.greenAccent.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (image.isPreliminary) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.2,
                      color: Colors.amberAccent.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 6),
          RatingFlagBar(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : _importImages,
              icon: Icon(
                Platform.isAndroid
                    ? Icons.folder_copy_outlined
                    : Icons.folder_open,
                size: 16,
              ),
              label: Text(
                Platform.isAndroid ? tr("folderImport") : tr("imageChoose"),
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, KeybindingState keys) {
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+Z / Ctrl+Shift+Z
    if (event is KeyDownEvent &&
        ctrl &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      final n = ref.read(historyNotifierProvider.notifier);
      HardwareKeyboard.instance.isShiftPressed ? n.redo() : n.undo();
      return KeyEventResult.handled;
    }

    final inCrop = ref.read(cropEditModeProvider);

    // Esc/Enter
    if (inCrop && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        cancelCrop(ref);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        commitCrop(ref);
        return KeyEventResult.handled;
      }
    }

    // 有修饰键时不单键绑定
    if (ctrl ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    // 自定义动作
    final action = keys.actionFor(event.logicalKey);
    if (action == null) return KeyEventResult.ignored;

    return _handleAction(action, event, inCrop);
  }

  KeyEventResult _handleAction(AppAction action, KeyEvent event, bool inCrop) {
    // hold：down 设 true、up 设 false
    if (action == AppAction.compareHold) {
      if (event is KeyDownEvent) {
        ref.read(compareBypassProvider.notifier).state = true;
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        ref.read(compareBypassProvider.notifier).state = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // KeyDown 触发
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (action) {
      case AppAction.toggleFullscreen:
        final cur = ref.read(fullscreenPreviewProvider);
        ref.read(fullscreenPreviewProvider.notifier).state = !cur;
        return KeyEventResult.handled;

      case AppAction.enterCrop:
        if (!inCrop) {
          enterCropMode(ref);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      // 打星/旗标
      case AppAction.rate0:
      case AppAction.rate1:
      case AppAction.rate2:
      case AppAction.rate3:
      case AppAction.rate4:
      case AppAction.rate5:
        if (inCrop) return KeyEventResult.ignored;
        final active = ref.read(activeShotPathProvider);
        if (active == null) return KeyEventResult.ignored;
        final rating = action.index - AppAction.rate0.index; // 0..5
        ref.read(shotsNotifierProvider.notifier).updateRating(active, rating);
        _writeSidecarNow(active);
        return KeyEventResult.handled;

      case AppAction.flagPick:
        if (inCrop) return KeyEventResult.ignored;
        return _toggleFlag(ShotFlag.pick);

      case AppAction.flagReject:
        if (inCrop) return KeyEventResult.ignored;
        return _toggleFlag(ShotFlag.reject);

      case AppAction.compareHold:
        return KeyEventResult.ignored;
    }
  }

  KeyEventResult _toggleFlag(ShotFlag flag) {
    final active = ref.read(activeShotPathProvider);
    if (active == null) return KeyEventResult.ignored;
    final cur = ref.read(activeShotProvider);
    final next = cur?.flag == flag ? ShotFlag.none : flag;
    ref.read(shotsNotifierProvider.notifier).updateFlag(active, next);
    _writeSidecarNow(active);
    return KeyEventResult.handled;
  }

  void _writeSidecarNow(String path) {
    if (!ref.read(sidecarEnabledProvider)) return;
    final shots = ref.read(shotsNotifierProvider);
    final idx = shots.indexWhere((s) => s.path == path);
    if (idx < 0) return;
    final s = shots[idx];
    ref.read(sidecarWriterProvider).writeNow(path, s.params, s.rating, s.flag);
  }

  Future<void> _syncToSelected() async {
    final selection = ref.read(exportSelectionNotifierProvider);
    if (selection.selectedPaths.isEmpty) {
      _snack(tr('syncNoTarget'));
      return;
    }
    final src = ref.read(currentParamsNotifierProvider);

    Set<SyncItem> items = {...kDefaultSyncItems};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('syncAdjustments')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'syncToCount',
                    args: ['${selection.selectedPaths.length}'],
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                for (final item in SyncItem.values)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: items.contains(item),
                    title: Text(
                      tr(item.labelKey),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: item == SyncItem.locals
                        ? Text(
                            tr('syncLocalsWarn'),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.orangeAccent.withValues(alpha: 0.8),
                            ),
                          )
                        : null,
                    onChanged: (v) => setS(() {
                      if (v == true) {
                        items.add(item);
                      } else {
                        items.remove(item);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: items.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text(tr('sync')),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    // 1) 更新状态
    ref
        .read(shotsNotifierProvider.notifier)
        .syncParamsToPaths(selection.selectedPaths, src, items);

    // 2) 持久化被同步的图（若开启）
    if (ref.read(sidecarEnabledProvider)) {
      final writer = ref.read(sidecarWriterProvider);
      final shots = ref.read(shotsNotifierProvider);
      for (final path in selection.selectedPaths) {
        final idx = shots.indexWhere((s) => s.path == path);
        if (idx < 0) continue;
        final shot = shots[idx];
        writer.writeNow(path, shot.params, shot.rating, shot.flag);
      }
    }

    _snack(
      tr('syncDone', args: ['${selection.selectedPaths.length}']),
      floating: true,
    );
  }

  Future<void> _importImages() async {
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
  }
}
