import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/lut/cube_lut.dart';
import '../core/models/adjustment_params.dart';
import '../render/preview_renderer.dart';
import '../services/camera/camera_controller.dart';
import '../services/camera/gphoto2_camera_controller.dart';
import '../services/camera/libgphoto2_android_controller.dart';
import '../widgets/adjustment_panel.dart';
import '../native/raw_bridge.dart';
import '../render/exporter.dart';
import '../widgets/camera_picker_dialog.dart';
import '../widgets/histogram_panel.dart';
import '../services/tether_watcher.dart';
import '../services/tethered_shot.dart';
import '../widgets/tether_widgets.dart';
import '../widgets/develop_sections.dart';

class RawSmokeTestScreen extends StatefulWidget {
  const RawSmokeTestScreen({super.key});
  @override
  State<RawSmokeTestScreen> createState() => _RawSmokeTestScreenState();
}

class _RawSmokeTestScreenState extends State<RawSmokeTestScreen> {
  // FFI 状态
  String _libRawVersion = 'loading...';
  String? _libRawError;

  // 解码状态
  String? _filePath;
  RawDecodedImage? _decoded;
  ui.Image? _uiImage;
  Duration? _decodeTime;
  Duration? _convertTime;
  String? _errorMessage;
  bool _busy = false;

  // State+
  Offset _histogramPosition = const Offset(8, 8);
  final panelWidth = 140.0;
  final panelHeight = 70.0;
  AdjustmentParams _params = AdjustmentParams.neutral;
  ui.Image? _lutTexture;
  int _lutSize = 0;
  String? _lutName;
  ui.FragmentProgram? _developProgram;
  TetherWatcher? _tether;
  final List<TetheredShot> _shots = [];
  TetheredShot? _activeShot;
  DateTime? _lastShotAt;
  StreamSubscription<File>? _shotSub;
  Timer? _statusTicker;
  bool _preserveParams = true;

  // 联机拍摄
  CameraController? _camera;
  StreamSubscription<CameraEvent>? _cameraSub;
  String? _cameraModel;
  bool _shutterFlash = false;

  static late final Uint8List _srgbLut = _buildSrgbLut();

  @override
  void initState() {
    super.initState();
    _probeFfi();
    _loadProgram();
  }

  void _probeFfi() {
    try {
      final v = RawBridge.libRawVersion();
      setState(() => _libRawVersion = v);
    } catch (e) {
      setState(() {
        _libRawVersion = 'FFI 加载失败';
        _libRawError = e.toString();
      });
    }
  }

  Future<void> _loadProgram() async {
    final p = await ui.FragmentProgram.fromAsset('shaders/develop.frag');
    if (mounted) setState(() => _developProgram = p);
  }

  Future<void> _pickAndDecode() async {
    final result = await FilePicker.platform.pickFiles(/* ... */);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path != null) await _decodeFromPath(path);
  }

  /// 把 16-bit linear RGB 转成 sRGB-encoded RGBA8 给 Flutter 显示
  Future<ui.Image> _toUiImage(RawDecodedImage img) async {
    final src = img.pixels;
    final w = img.width, h = img.height;
    final rgba = Uint8List(w * h * 4);
    final lut = _srgbLut;

    if (src is Uint16List) {
      for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
        rgba[j] = lut[src[i]];
        rgba[j + 1] = lut[src[i + 1]];
        rgba[j + 2] = lut[src[i + 2]];
        rgba[j + 3] = 255;
      }
    } else if (src is Uint8List) {
      for (int i = 0, j = 0; i < src.length; i += 3, j += 4) {
        rgba[j] = src[i];
        rgba[j + 1] = src[i + 1];
        rgba[j + 2] = src[i + 2];
        rgba[j + 3] = 255;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// 16-bit linear → 8-bit sRGB
  static Uint8List _buildSrgbLut() {
    final lut = Uint8List(65536);
    for (int i = 0; i < 65536; i++) {
      final l = i / 65535.0;
      final s = l <= 0.0031308
          ? l * 12.92
          : 1.055 * math.pow(l, 1.0 / 2.4) - 0.055;
      lut[i] = (s.clamp(0.0, 1.0) * 255.0).round();
    }
    return lut;
  }

  Future<void> _loadLutFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const ['cube'],
    );

    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    if (Platform.isAndroid) {
      if (!path.toLowerCase().endsWith('.cube')) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请选择有效的 .cube 格式文件')));
        return;
      }
    }

    await _applyLut(() => CubeLut.fromFile(path));
  }

  Future<void> _loadLutBuiltin(CubeLut Function() factory) async {
    await _applyLut(() async => factory());
  }

  Future<void> _applyLut(Future<CubeLut> Function() loader) async {
    try {
      final lut = await loader();
      final tex = await lut.toHaldStrip();
      if (!mounted) return;
      setState(() {
        _lutTexture = tex;
        _lutSize = lut.size;
        _lutName = lut.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('LUT 加载失败: $e')));
    }
  }

  Future<void> _showExportDialog() async {
    if (_filePath == null || _developProgram == null) return;

    ExportFormat format = ExportFormat.png;
    int quality = 95;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('导出图像'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('格式', style: TextStyle(fontSize: 12)),
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
                Text('质量: $quality', style: const TextStyle(fontSize: 12)),
                Slider(
                  value: quality.toDouble(),
                  min: 50,
                  max: 100,
                  onChanged: (v) => setS(() => quality = v.round()),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '将以全分辨率渲染并保存。可能耗时较久。',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final defaultName = _filePath!
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '_edited.${format.extension}');
    final saveResult = await FilePicker.platform.saveFile(
      dialogTitle: '保存到...',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [format.extension],
    );
    if (saveResult == null) return;

    await _runExport(saveResult, format, quality);
  }

  Future<void> _runExport(String outPath, ExportFormat fmt, int quality) async {
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<(double, String)>((0, '准备...'));

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

    try {
      final stopwatch = Stopwatch()..start();
      await Exporter.exportFullRes(
        inputRawPath: _filePath!,
        outputPath: outPath,
        format: fmt,
        shaderProgram: _developProgram!,
        params: _params,
        lutTexture: _lutTexture,
        lutSize: _lutSize,
        jpegQuality: quality,
        onProgress: (f, s) => progressNotifier.value = (f, s),
      );
      stopwatch.stop();
      if (mounted) Navigator.pop(context); // 关 progress dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('导出完成 · ${stopwatch.elapsed.inSeconds}s · $outPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e, st) {
      if (mounted) Navigator.pop(context);
      debugPrint('Export error: $e\n$st');
      messenger.showSnackBar(SnackBar(content: Text('导出失败: $e')));
    } finally {
      progressNotifier.dispose();
    }
  }

  Future<void> _stopTether() async {
    // 停止文件监听
    await _shotSub?.cancel();
    _statusTicker?.cancel();
    await _tether?.dispose();
    for (final s in _shots) {
      s.dispose();
    }

    // 停止相机传输
    if(_camera != null && _camera!.isActive){
      await _camera!.stopTether();
    }

    if (!mounted) return;
    setState(() {
      _tether = null;
      _shots.clear();
      _camera = null;
      _activeShot = null;
      _lastShotAt = null;
      _shotSub = null;
      _statusTicker = null;
    });
  }

  Future<void> _onNewShot(File file) async {
    final shot = TetheredShot(
      path: file.path,
      filename: p.basename(file.path),
      detectedAt: DateTime.now(),
      params: _preserveParams ? _params : AdjustmentParams.neutral,
    );
    setState(() {
      _shots.add(shot);
      _lastShotAt = shot.detectedAt;
    });

    unawaited(
      shot.loadThumbnail().then((_) {
        if (mounted) setState(() {});
      }),
    );

    await _selectShot(shot);
  }

  Future<void> _selectShot(TetheredShot shot) async {
    setState(() {
      _activeShot = shot;
      _params = shot.params;
    });
    await _decodeFromPath(shot.path);
  }

  Future<void> _decodeFromPath(String path) async {
    setState(() {
      _busy = true;
      _filePath = path;
      _decoded = null;
      _uiImage = null;
      _decodeTime = null;
      _convertTime = null;
      _errorMessage = null;
    });
    try {
      final sw1 = Stopwatch()..start();
      final img = await RawBridge.decodePreview(path);
      sw1.stop();
      final sw2 = Stopwatch()..start();
      final uiImg = await _toUiImage(img);
      sw2.stop();
      if (!mounted) return;
      setState(() {
        _decoded = img;
        _uiImage = uiImg;
        _decodeTime = sw1.elapsed;
        _convertTime = sw2.elapsed;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _busy = false;
      });
    }
  }

  CameraController _createCameraController() {
    if (Platform.isAndroid) {
      return LibGphoto2AndroidController();
    }
    return Gphoto2CameraController(); // Windows/Linux/macOS
  }

  Future<void> _startCameraTether() async {
    final controller = _createCameraController();
    final pick = await showDialog<CameraPickResult>(
      context: context,
      builder: (_) => CameraPickerDialog(controller: controller),
    );
    if (pick == null) return;

    // 启动文件夹监控
    await _startWatcher(pick.saveFolder);
    if (_tether == null) return; // watcher 启动失败

    // 2. 启动 gphoto2 进程
    setState(() {
      _camera = controller;
      _cameraModel = pick.camera.model;
    });

    _cameraSub = controller
        .startTether(camera: pick.camera, saveFolder: pick.saveFolder)
        .listen(_onCameraEvent);
  }

  void _onCameraEvent(CameraEvent ev) {
    switch (ev) {
      case CameraConnected():
        break;
      case CameraTakingShot():
        setState(() => _shutterFlash = true);
        Future.delayed(
          const Duration(milliseconds: 200),
          () => mounted ? setState(() => _shutterFlash = false) : null,
        );
        break;
      case CameraShotSaved():
        break;
      case CameraError(:final message):
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('相机错误: $message')));
        break;
      case CameraDisconnected():
        if (mounted) _stopCameraTether();
        break;
    }
  }

  Future<void> _stopCameraTether() async {
    await _cameraSub?.cancel();
    await _camera?.stopTether();
    if (mounted) {
      setState(() {
        _camera = null;
        _cameraModel = null;
        _cameraSub = null;
      });
    }
    await _stopTether();
  }

  Future<void> _startTether() async {
    String? folder;
    folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择监控文件夹',
    );
    if (folder == null || folder.isEmpty) return;
    await _startWatcher(folder);
  }

  Future<void> _startWatcher(String folder) async {
    final watcher = TetherWatcher(folder);
    try {
      await watcher.start();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法监控: $e')));
      return;
    }
    setState(() {
      _tether = watcher;
      _shots.clear();
      _activeShot = null;
      _lastShotAt = null;
    });
    _shotSub = watcher.onShot.listen(_onNewShot);
    _statusTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _stopTether();
    super.dispose();
  }

  void _clearLut() {
    setState(() {
      _lutTexture?.dispose();
      _lutTexture = null;
      _lutSize = 0;
      _lutName = null;
    });
  }

  void _onParamsChanged(AdjustmentParams p) {
    setState(() {
      _params = p;
      if (_preserveParams) {
        // 同步到所有 shot
        for (final s in _shots) {
          s.params = p;
        }
      } else {
        // 仅写到当前 shot
        _activeShot?.params = p;
      }
    });
  }

  void _togglePreserve(bool value) {
    setState(() {
      _preserveParams = value;
      if (value) {
        for (final s in _shots) {
          s.params = _params;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    return Scaffold(
      body: SafeArea(
        child: isPhone ? _buildPhoneLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildPhoneLayout() {
    final hasImage = _uiImage != null && _developProgram != null;

    return Column(
      children: [
        _buildTopBar(),
        if (_tether != null)
          TetherStatusBar(
            watchPath: _cameraModel != null
                ? '$_cameraModel → ${_tether!.watchPath}'
                : _tether!.watchPath,
            shotCount: _shots.length,
            lastShotAt: _lastShotAt,
            onStop: _camera != null ? _stopCameraTether : _stopTether,
            preserveParams: _preserveParams,
            onPreserveChanged: _togglePreserve,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );

              return Stack(
                children: [
                  Positioned.fill(child: _buildPreviewArea()),
                  if (hasImage)
                    Positioned(
                      left: _histogramPosition.dx,
                      top: _histogramPosition.dy,
                      width: 140,
                      height: 70,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _histogramPosition = Offset(
                              (_histogramPosition.dx + details.delta.dx).clamp(
                                0.0,
                                previewSize.width - panelWidth,
                              ),
                              (_histogramPosition.dy + details.delta.dy).clamp(
                                0.0,
                                previewSize.height - panelHeight,
                              ),
                            );
                          });
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Opacity(
                            opacity: 0.9,
                            child: LiveHistogramPanel(
                              program: _developProgram!,
                              sourceImage: _uiImage,
                              params: _params,
                              lutTexture: _lutTexture,
                              lutSize: _lutSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // Tether thumb strip
        if (_tether != null && _shots.isNotEmpty)
          TetherThumbStrip(
            shots: _shots,
            activeShot: _activeShot,
            onSelect: _selectShot,
          ),
        _buildPhoneInfoBar(),
        if (hasImage) _buildPhoneToolPanel(),
      ],
    );
  }

  Widget _buildPhoneInfoBar() {
    final m = _decoded?.metadata;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              m == null
                  ? (_filePath ?? '尚未选择文件')
                  : '${m.cameraModel} · ISO ${m.iso} · ${m.shutterDisplay} · f/${m.aperture.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_decoded != null)
            Text(
              '${_decoded!.width}×${_decoded!.height}',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.greenAccent.withOpacity(0.8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhoneToolPanel() {
    return SizedBox(
      height: 320,
      child: DefaultTabController(
        length: 4,
        child: Container(
          color: const Color(0xFF14141A),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: const TextStyle(fontSize: 12),
                        tabs: const [
                          Tab(text: 'Light', height: 36),
                          Tab(text: 'Color', height: 36),
                          Tab(text: 'HSL', height: 36),
                          Tab(text: 'LUT', height: 36),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Reset all',
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
                        params: _params,
                        onChanged: _onParamsChanged,
                      ),
                    ),
                    SingleChildScrollView(
                      child: WhiteBalanceColorSection(
                        params: _params,
                        onChanged: _onParamsChanged,
                      ),
                    ),
                    SingleChildScrollView(
                      child: HslSection(
                        bands: _params.hsl,
                        onChanged: (b) =>
                            _onParamsChanged(_params.copyWith(hsl: b)),
                      ),
                    ),
                    SingleChildScrollView(
                      child: LutSection(
                        lutName: _lutName,
                        intensity: _params.lutIntensity,
                        onIntensityChanged: (v) =>
                            _onParamsChanged(_params.copyWith(lutIntensity: v)),
                        onPick: _loadLutFromFile,
                        onLoadTest: () =>
                            _loadLutBuiltin(CubeLut.testCinematic),
                        onLoadIdentity: () => _loadLutBuiltin(CubeLut.identity),
                        onClear: _clearLut,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        _buildTopBar(),
        // 联机状态条
        if (_tether != null)
          TetherStatusBar(
            watchPath: _cameraModel != null
                ? '${_cameraModel} → ${_tether!.watchPath}'
                : _tether!.watchPath,
            shotCount: _shots.length,
            lastShotAt: _lastShotAt,
            onStop: _camera != null ? _stopCameraTether : _stopTether,
            preserveParams: _preserveParams,
            onPreserveChanged: _togglePreserve,
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildPreviewArea()),
              if (_uiImage != null)
                AdjustmentPanel(
                  params: _params,
                  onChanged: _onParamsChanged,
                  lutName: _lutName,
                  onPickLut: _loadLutFromFile,
                  onLoadTestLut: () => _loadLutBuiltin(CubeLut.testCinematic),
                  onLoadIdentity: () => _loadLutBuiltin(CubeLut.identity),
                  onClearLut: _clearLut,
                  histogram: _developProgram == null
                      ? null
                      : LiveHistogramPanel(
                          program: _developProgram!,
                          sourceImage: _uiImage,
                          params: _params,
                          lutTexture: _lutTexture,
                          lutSize: _lutSize,
                        ),
                ),
            ],
          ),
        ),
        // 缩略图条
        if (_tether != null && _shots.isNotEmpty)
          TetherThumbStrip(
            shots: _shots,
            activeShot: _activeShot,
            onSelect: _selectShot,
          ),
        _buildBottomPanel(),
      ],
    );
  }

  Widget _buildTopBar() {
    final ok = _libRawError == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          if (_tether == null)
            IconButton(
              icon: const Icon(Icons.cable_rounded, size: 18),
              tooltip: '文件夹监控',
              onPressed: _startTether,
            ),
          if (_camera == null && _tether == null)
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              tooltip: '联机拍摄（USB / WSL）',
              onPressed: _startCameraTether,
            )
          else if (_camera != null)
            IconButton(
              icon: Icon(
                Icons.photo_camera,
                size: 18,
                color: _shutterFlash
                    ? Colors.greenAccent
                    : Colors.greenAccent.withOpacity(0.85),
              ),
              tooltip: '${_cameraModel ?? '相机'} 已联机（点击断开）',
              onPressed: _stopCameraTether,
            ),
          const SizedBox(width: 4),
          if (_uiImage != null && _developProgram != null) ...[
            IconButton(
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              tooltip: '导出',
              onPressed: _showExportDialog,
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            Icons.camera_outlined,
            color: Colors.white.withOpacity(0.85),
            size: 20,
          ),
          const SizedBox(width: 10),
          const Text(
            'e4pix · stage 1 smoke test',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ok ? const Color(0xFF1F3A2A) : const Color(0xFF3A1F1F),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ok ? 'LibRaw $_libRawVersion' : 'LibRaw FAILED',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: ok ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    if (_libRawError != null) {
      return _CenterMessage(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        title: '无法加载 e4pix_raw.dll',
        body: _libRawError!,
      );
    }
    if (_busy) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_errorMessage != null) {
      return _CenterMessage(
        icon: Icons.warning_amber_rounded,
        color: Colors.orangeAccent,
        title: '解码失败',
        body: _errorMessage!,
      );
    }
    if (_uiImage == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pickAndDecode,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择 RAW 文件'),
            ),
            const SizedBox(height: 8),
            Text(
              'ARW · CR2 · CR3 · NEF · RAF · DNG · ORF · RW2 …',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.4),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: PreviewRenderer(
        image: _uiImage!,
        params: _params,
        lutTexture: _lutTexture,
        lutSize: _lutSize,
      ),
    );
  }

  Widget _buildBottomPanel() {
    final m = _decoded?.metadata;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _filePath ?? '尚未选择文件',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
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
                if (_decoded != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_decoded!.width} × ${_decoded!.height} · '
                    '${_decoded!.bitsPerChannel}-bit · '
                    'decode ${_decodeTime!.inMilliseconds}ms · '
                    'convert ${_convertTime!.inMilliseconds}ms',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.greenAccent.withOpacity(0.8),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickAndDecode,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Pick RAW'),
          ),
        ],
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
                  color: Colors.white.withOpacity(0.7),
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
