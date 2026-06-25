import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LogEntry {
  final DateTime time;
  final String message;
  LogEntry(this.time, this.message);

  String toLine() {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '[$h:$m:$s] $message';
  }
}

class DebugLogService {
  static final instance = DebugLogService._();
  DebugLogService._();

  static const maxEntries = 2000;
  final List<LogEntry> _entries = [];
  bool enabled = false;
  bool _loaded = false;
  File? _logFile;

  /// 新日志通知
  final ValueNotifier<int> logCount = ValueNotifier(0);

  /// 从磁盘加载历史日志（首次调用时执行）
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(dir.path, 'debug_log.txt'));
      if (await _logFile!.exists()) {
        final lines = await _logFile!.readAsLines();
        for (final line in lines) {
          // 格式: [HH:MM:SS] message
          final match = RegExp(
            r'^\[(\d{2}):(\d{2}):(\d{2})\] (.*)$',
          ).firstMatch(line);
          if (match != null) {
            final now = DateTime.now();
            final time = DateTime(
              now.year,
              now.month,
              now.day,
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
              int.parse(match.group(3)!),
            );
            _entries.add(LogEntry(time, match.group(4)!));
          }
        }
        // 超过上限时截断旧日志
        while (_entries.length > maxEntries) {
          _entries.removeAt(0);
        }
        logCount.value = _entries.length;
      }
    } catch (e) {
      debugPrint('[DebugLog] Failed to load log file: $e');
    }
  }

  void add(String message) {
    if (!enabled) return;

    final entry = LogEntry(DateTime.now(), message);
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    logCount.value = _entries.length;

    // 同步写入磁盘，确保崩溃时不丢日志
    _writeLine(entry.toLine());
  }

  /// 同步追加一行到日志文件
  void _writeLine(String line) {
    try {
      if (_logFile != null) {
        _logFile!.writeAsStringSync(
          '$line\n',
          mode: FileMode.append,
          flush: true,
        );
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    _entries.clear();
    logCount.value = 0;
    // 清空文件
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
    } catch (_) {}
  }

  List<LogEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  Future<File> exportToFile() async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File(p.join(dir.path, 'e4pix_log_$ts.txt'));
    final content = _entries.map((e) => e.toLine()).join('\n');
    return file.writeAsString(content);
  }
}
