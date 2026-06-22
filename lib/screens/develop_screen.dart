import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models/adjustment_params.dart';
import '../core/models/export_config.dart';
import '../core/models/export_job.dart';
import '../core/models/sync_options.dart';
import '../core/models/tethered_shot.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/ai/ai_color_service.dart';
import '../services/ai/ai_input_renderer.dart';
import '../services/ai/ai_settings.dart';
import '../services/lens/lensfun_database.dart';
import '../services/app/app_settings.dart';
import '../services/app/update_service.dart';
import '../state/providers.dart';
import '../widgets/develop/horizontal_adjustment_panel.dart';
import '../widgets/ai/ai_settings_dialog.dart';
import '../widgets/ai/ai_suggestion_dialog.dart';
import '../widgets/tether/camera_picker_dialog.dart';
import '../widgets/develop/develop_misc_widgets.dart';
import '../widgets/develop/develop_top_bar.dart';
import '../widgets/export/export_dialog.dart';
import '../widgets/preview/preview_area.dart';
import '../core/keybindings/develop_key_handler.dart';
import 'folder_import_screen.dart';
import '../widgets/develop/histogram_panel.dart';
import '../widgets/app/image_info_bar.dart';
import '../widgets/develop/vertical_adjustment_panel.dart';
import '../widgets/develop/sections/preset_section.dart';
import '../widgets/tether/tether_widgets.dart';
import 'settings_screen.dart';

class DevelopScreen extends ConsumerStatefulWidget {
  const DevelopScreen({super.key});
  @override
  ConsumerState<DevelopScreen> createState() => _DevelopScreenState();
}

class _DevelopScreenState extends ConsumerState<DevelopScreen> {
  Offset _histogramPosition = const Offset(8, 8);
  bool _immersiveOn = false;
  static const _miniHistogramW = 140.0;
  static const _miniHistogramH = 70.0;

  // 底部面板动态高度
  double _bottomPanelHeight = 400;
  static const _bottomPanelMinHeight = 250.0;
  static const _bottomPanelMaxHeight = 520.0;
  static const _handleBarHeight = 14.0; // 拖拽手柄高度

  // 底部面板折叠状态（仅隐藏图片滑块，不改变面板高度）
  bool _bottomPanelCollapsed = false;

  // 拖拽去抖累加器（避免每帧 setState 重建子树）
  double _panelDragAccum = 0;
  Offset _histDragAccum = Offset.zero;
  static const _panelDragThreshold = 4.0;
  static const _histDragThreshold = 3.0;

  @override
  void initState() {
    super.initState();
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
            style: AppTypography.bodyLarge,
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
    if (!mounted) return;
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
    if (!mounted) return;

    // 记住模板
    ref.read(exportTemplateProvider.notifier).set(result.filenameTemplate);
    final folder = await FilePicker.getDirectoryPath(dialogTitle: tr('saveTo'));
    if (folder == null || !mounted) return;

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
    // 加载lensfun数据库
    ref.listen(imageNotifierProvider, (prev, next) {
      if (next.value != null && prev?.value == null) {
        LensfunDatabase.instance.ensureLoaded();
      }
    });
    if (isFullscreen) {
      return _buildFullscreen();
    }

    return PopScope(
      canPop: false,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => handleDevelopKeyEvent(ref, event, keys),
        child: Scaffold(
          body: SafeArea(
            left: isVertical,
            child: isVertical
                ? _buildVerticalLayout()
                : _buildHorizontalLayout(),
          ),
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

  // 集中读取两个布局共用的 9 个 provider，消除重复
  ({
    TetherSession? session,
    List<TetheredShot> shots,
    TetheredShot? activeShot,
    ExportSelection selection,
    bool preserve,
    DecodedImageState? image,
    ui.FragmentProgram? program,
    CameraState cameraState,
    bool cropEditMode,
  })
  _buildLayoutData() {
    return (
      session: ref.watch(tetherSessionNotifierProvider),
      shots: ref.watch(shotsNotifierProvider),
      activeShot: ref.watch(activeShotProvider),
      selection: ref.watch(exportSelectionNotifierProvider),
      preserve: ref.watch(preserveParamsProvider),
      image: ref.watch(imageNotifierProvider).value,
      program: ref.watch(shaderProgramProvider).value,
      cameraState: ref.watch(cameraNotifierProvider),
      cropEditMode: ref.watch(cropEditModeProvider),
    );
  }

  /// 统一卡片包裹器 — 圆角 + 悬浮间距
  Widget _buildFloatingCard({
    required Widget child,
    double? width,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(10)),
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildVerticalLayout() {
    final d = _buildLayoutData();
    final hasImage = d.image != null && d.program != null;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildFloatingCard(
            child: DevelopTopBar(
              onExport: _showExportDialog,
              onSync: _syncToSelected,
              onTetherFolder: _startFolderTether,
              onTetherCamera: _startCameraTether,
              onStopTether: _stopAllTether,
              onAI: _showAISuggestion,
              onAILongPress: _showAISettings,
            ),
          ),
          const SizedBox(height: 12),
          if (d.session != null) ...[
            _buildFloatingCard(
              child: _buildTetherStatusBar(
                d.session!,
                d.shots.length,
                d.preserve,
                d.cameraState,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const AIBanner(),
          // ── 预览区域：悬浮卡片 ──
          Expanded(
            child: _buildFloatingCard(
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
                              _histDragAccum += details.delta;
                              if (_histDragAccum.distance <
                                  _histDragThreshold) {
                                return;
                              }
                              setState(() {
                                _histogramPosition = Offset(
                                  (_histogramPosition.dx + _histDragAccum.dx)
                                      .clamp(
                                        0.0,
                                        previewSize.width - _miniHistogramW,
                                      ),
                                  (_histogramPosition.dy + _histDragAccum.dy)
                                      .clamp(
                                        0.0,
                                        previewSize.height - _miniHistogramH,
                                      ),
                                );
                              });
                              _histDragAccum = Offset.zero;
                            },
                            onPanEnd: (_) => _histDragAccum = Offset.zero,
                            onPanCancel: () => _histDragAccum = Offset.zero,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Opacity(
                                opacity: 0.9,
                                child: _buildHistogram(d.program!, d.image!),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (hasImage) ...[
            const SizedBox(height: 12),
            // 底部调整面板：悬浮卡片 可拖拽高度 + 折叠
            _buildFloatingCard(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: _bottomPanelHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 拖拽手柄 — 点击折叠 / 恢复图片滑块
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _bottomPanelCollapsed = !_bottomPanelCollapsed;
                        });
                      },
                      onVerticalDragUpdate: (details) {
                        _panelDragAccum += details.delta.dy;
                        if (_panelDragAccum.abs() < _panelDragThreshold) return;
                        setState(() {
                          _bottomPanelHeight =
                              (_bottomPanelHeight - _panelDragAccum).clamp(
                                _bottomPanelMinHeight,
                                _bottomPanelMaxHeight,
                              );
                        });
                        _panelDragAccum = 0;
                      },
                      onVerticalDragEnd: (_) => _panelDragAccum = 0,
                      onVerticalDragCancel: () => _panelDragAccum = 0,
                      child: Container(
                        height: _handleBarHeight,
                        color: AppColors.subtleBorder,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.faintText,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 图片滑块 — 点击手柄折叠 / 恢复
                    if (!_bottomPanelCollapsed &&
                        d.shots.isNotEmpty &&
                        !d.cropEditMode)
                      TetherThumbStrip(
                        shots: ref.watch(filteredShotsProvider),
                        activeShot: d.activeShot,
                        onSelect: _onThumbTap,
                        multiSelectMode: d.selection.multiSelectMode,
                        selectedShots: ref.watch(selectedShotsProvider),
                      ),
                    // 信息栏
                    ImageInfoBar(onImport: _importImages),
                    // 调整面板 — 填充剩余空间
                    Expanded(
                      child: VerticalAdjustmentPanel(
                        onChanged: _onParamsChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            ImageInfoBar(onImport: _importImages),
        ],
      ),
    );
  }

  Widget _buildHorizontalLayout() {
    final d = _buildLayoutData();
    final params = ref.watch(currentParamsNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildFloatingCard(
            child: DevelopTopBar(
              onExport: _showExportDialog,
              onSync: _syncToSelected,
              onTetherFolder: _startFolderTether,
              onTetherCamera: _startCameraTether,
              onStopTether: _stopAllTether,
              onAI: _showAISuggestion,
              onAILongPress: _showAISettings,
            ),
          ),
          const SizedBox(height: 12),
          if (d.session != null) ...[
            _buildFloatingCard(
              child: _buildTetherStatusBar(
                d.session!,
                d.shots.length,
                d.preserve,
                d.cameraState,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const AIBanner(),
          Expanded(
            child: Row(
              children: [
                if (d.shots.isNotEmpty && !d.cropEditMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildFloatingCard(
                      child: TetherThumbStrip(
                        shots: ref.watch(filteredShotsProvider),
                        activeShot: d.activeShot,
                        onSelect: _onThumbTap,
                        multiSelectMode: d.selection.multiSelectMode,
                        selectedShots: ref.watch(selectedShotsProvider),
                        axis: Axis.vertical,
                      ),
                    ),
                  ),
                Expanded(child: _buildFloatingCard(child: const PreviewArea())),
                if (d.image != null) ...[
                  const SizedBox(width: 12),
                  _buildFloatingCard(
                    width: 340,
                    child: HorizontalAdjustmentPanel(
                      params: params,
                      onChanged: _onParamsChanged,
                      histogram: d.program == null
                          ? null
                          : _buildHistogram(d.program!, d.image!),
                      presetBar: const PresetBar(),
                      info: ImageInfoBar(onImport: _importImages),
                      onEnterCrop: () => enterCropMode(ref),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTetherStatusBar(
    TetherSession session,
    int shotCount,
    bool preserve,
    CameraState cameraState,
  ) {
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
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.mediumText,
                  ),
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
                      style: AppTypography.bodyLarge,
                    ),
                    subtitle: item == SyncItem.locals
                        ? Text(
                            tr('syncLocalsWarn'),
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.semanticWarning.withValues(
                                alpha: 0.8,
                              ),
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

    if (!mounted || ok != true) return;

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
  }
}
