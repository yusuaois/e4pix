import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../native/raw_bridge.dart';

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

  static late final Uint8List _srgbLut = _buildSrgbLut();

  @override
  void initState() {
    super.initState();
    _probeFfi();
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

  Future<void> _pickAndDecode() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'arw',
        'cr2',
        'cr3',
        'nef',
        'nrw',
        'raf',
        'dng',
        'orf',
        'rw2',
        'pef',
        'srw',
        'rwl',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

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
      // 1. 解码
      final sw1 = Stopwatch()..start();
      final img = await RawBridge.decodePreview(path);
      sw1.stop();

      // 2. 转 ui.Image（含 sRGB encode）
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
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _busy = false;
      });
      debugPrint('Decode error: $e\n$st');
    }
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

  /// 16-bit linear → 8-bit sRGB 查找表（启动一次，~256KB 内存）
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildPreviewArea()),
          _buildBottomPanel(),
        ],
      ),
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
      child: Center(
        child: RawImage(image: _uiImage, fit: BoxFit.contain),
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
