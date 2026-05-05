import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// 监控指定文件夹中新出现的 RAW 文件。
/// 关键点：等待文件写入稳定再上报（避免读到半截文件）。
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

  /// 已经稳定写入的新 RAW 文件流。
  Stream<File> get onShot => _controller.stream;
  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    final dir = Directory(watchPath);
    if (!await dir.exists()) {
      throw Exception('文件夹不存在: $watchPath');
    }

    // 启动时先把已有文件标记为"已见"，避免误触发
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
          if (++stableCount >= 2) return true;
        } else {
          stableCount = 0;
        }
        lastSize = size;
      } catch (_) {
        // 可能被独占写，下次重试
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