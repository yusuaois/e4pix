import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:watcher/watcher.dart';

// 监听文件夹
class TetherWatcher {
  static const _rawExtensions = {
    '.arw', '.cr2', '.cr3', '.nef', '.nrw', '.raf',
    '.dng', '.orf', '.rw2', '.pef', '.srw', '.rwl',
  };

  final String watchPath;
  final Set<String> _seen = {};
  StreamSubscription? _sub;
  final StreamController<File> _controller = StreamController<File>.broadcast();
  bool _isRunning = false;

  TetherWatcher(this.watchPath);

  Stream<File> get onShot => _controller.stream;
  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    if (Platform.isAndroid) {
      bool granted = await _requestAndroidPermission();
      if (!granted) {
        throw Exception('Android 端需要“所有文件访问权限”才能监听其他 App 的照片。');
      }
    }

    final dir = Directory(watchPath);
    if (!await dir.exists()) {
      throw Exception('文件夹不存在: $watchPath');
    }

    // 标记已有RAW
    await for (final entity in dir.list(recursive: false)) {
      if (entity is File && _isRaw(entity.path)) {
        _seen.add(entity.path);
      }
    }

    // 注册 watcher
    final watcher = DirectoryWatcher(watchPath);
    _sub = watcher.events.listen(_onEvent);
    _isRunning = true;
  }

  Future<bool> _requestAndroidPermission() async {
    // 检查是否已经授权
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    // 尝试请求
    status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      // TODO 如果用户在设置里拒绝了，引导用户去设置页
      return false;
    }
    return true;
  }

  Future<void> _onEvent(WatchEvent ev) async {
    if (ev.type != ChangeType.ADD && ev.type != ChangeType.MODIFY) return;
    if (!_isRaw(ev.path) || _seen.contains(ev.path)) return;

    final file = File(ev.path);
    final stable = await _waitUntilStable(file);
    if (!stable) return;
    if (_seen.contains(ev.path)) return; // 双重检查

    _seen.add(ev.path);
    if (!_controller.isClosed) _controller.add(file);
  }

  bool _isRaw(String path) =>
      _rawExtensions.contains(p.extension(path).toLowerCase());

  /// 轮询大小不再变化才认为写入完成。
  Future<bool> _waitUntilStable(File f, {int maxAttempts = 40}) async {
    int? lastSize;
    int stableCount = 0;
    for (int i = 0; i < maxAttempts; i++) {
      try {
        if (!await f.exists()) return false;
        final size = await f.length();
        if (size > 0 && lastSize == size) {
          if (++stableCount >= 3) return true;
        } else {
          stableCount = 0;
        }
        lastSize = size;
      } catch (_) {
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _sub?.cancel();
    _sub = null;
    _seen.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}