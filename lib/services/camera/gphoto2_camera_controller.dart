import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'camera_controller.dart';

class Gphoto2CameraController implements CameraController {
  Process? _process;
  StreamController<CameraEvent>? _events;
  bool _active = false;

  @override
  bool get isActive => _active;

  // Windows WSL：'wsl' + ['gphoto2', ...args]
  // Linux/macOS ：'gphoto2' + args
  String get _exe => Platform.isWindows ? 'wsl' : 'gphoto2';
  List<String> _gpArgs(List<String> args) =>
      Platform.isWindows ? ['gphoto2', ...args] : args;

  String _toShellPath(String path) {
    if (!Platform.isWindows) return path;
    if (path.length < 2 || path[1] != ':') return path;
    final drive = path[0].toLowerCase();
    final rest = path.substring(2).replaceAll(r'\', '/');
    return '/mnt/$drive$rest';
  }

  // 探测相机
  @override
  Future<List<DetectedCamera>> detectCameras() async {
    late final ProcessResult res;
    try {
      res = await Process.run(_exe, _gpArgs(['--auto-detect']))
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw CameraException('gphoto2 探测超时——WSL 是否可用？');
    } catch (e) {
      throw CameraException('无法启动 gphoto2: $e\n'
          '请确认：\n'
          '  - Windows: 已装 WSL + Ubuntu + gphoto2\n'
          '  - Linux/macOS: gphoto2 已在 PATH 中');
    }

    if (res.exitCode != 0) {
      throw CameraException('gphoto2 报错: ${res.stderr}');
    }
    return _parseAutoDetect(res.stdout as String);
  }

  static final _cameraLineRe =
      RegExp(r'^(.+?)\s{2,}(usb:\S+|ptpip:\S+)\s*$');

  List<DetectedCamera> _parseAutoDetect(String out) {
    final cameras = <DetectedCamera>[];
    for (final raw in out.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('Model') || line.startsWith('---')) continue;
      final m = _cameraLineRe.firstMatch(line);
      if (m != null) {
        cameras.add(DetectedCamera(
          model: m.group(1)!.trim(),
          port: m.group(2)!.trim(),
        ));
      }
    }
    return cameras;
  }

  // 启动 tether
  @override
  Stream<CameraEvent> startTether({
    required DetectedCamera camera,
    required String saveFolder,
  }) {
    if (_active) {
      throw CameraException('已有 tether 会话在运行');
    }
    _active = true;
    _events = StreamController<CameraEvent>.broadcast();
    _spawn(camera, saveFolder);
    return _events!.stream;
  }

  Future<void> _spawn(DetectedCamera camera, String saveFolder) async {
    try {
      final shellPath = _toShellPath(saveFolder);

      //   --port            指定相机
      //   --capture-tethered 阻塞监听快门事件
      //   --filename %f.%C  保留相机原始命名
      final args = [
        '--port', camera.port,
        '--capture-tethered',
        '--filename', '$shellPath/%f.%C',
      ];

      _process = await Process.start(
        _exe,
        _gpArgs(args),
        runInShell: false,
      );

      _events?.add(CameraConnected(camera.model));

      // stdout：状态信息
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStdoutLine);

      // stderr：错误信息
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        if (line.contains('ERROR') || line.contains('*** Error')) {
          _events?.add(CameraError(line.trim()));
        }
      });

      // 进程退出
      final exitCode = await _process!.exitCode;
      _active = false;
      if (exitCode != 0 && _events != null && !_events!.isClosed) {
        _events!.add(CameraError('gphoto2 退出码 $exitCode'));
      }
      _events?.add(const CameraDisconnected());
      await _events?.close();
      _events = null;
      _process = null;
    } catch (e) {
      _events?.add(CameraError('启动失败: $e'));
      _active = false;
      await _events?.close();
      _events = null;
    }
  }

  void _onStdoutLine(String line) {
    final t = line.trim();
    if (t.isEmpty || _events == null) return;
    if (t.startsWith('Saving file as ')) {
      final filename = t.substring('Saving file as '.length);
      _events!.add(CameraShotSaved(filename));
    } else if (t.contains('UNKNOWN PTP Event c107')) {
      // 快门已按
      _events!.add(const CameraTakingShot());
    }
  }

  // 停止
  @override
  Future<void> stopTether() async {
    if (!_active) return;
    final p = _process;
    if (p != null) {
      if (Platform.isWindows) {
        p.kill(ProcessSignal.sigterm);
      } else {
        p.kill(ProcessSignal.sigint);
      }
      try {
        await p.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        p.kill(ProcessSignal.sigkill);
      }
    }
    _active = false;
  }
}