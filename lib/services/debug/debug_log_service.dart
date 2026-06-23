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

  /// 新日志通知
  final ValueNotifier<int> logCount = ValueNotifier(0);

  void add(String message) {
    if (!enabled) return;
    _entries.add(LogEntry(DateTime.now(), message));
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    logCount.value = _entries.length;
  }

  void clear() {
    _entries.clear();
    logCount.value = 0;
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
