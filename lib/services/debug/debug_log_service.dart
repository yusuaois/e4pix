import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogEntry {
  final DateTime time;
  final String message;
  final String? tag;
  final String level; // 'error' | 'warning' | 'info'

  LogEntry(this.time, this.message, {this.tag, this.level = 'info'});

  String toLine() {
    final y = time.year.toString().padLeft(4, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '[$y-$mo-$d $h:$m:$s] $message';
  }
}

class DebugLogService {
  static final instance = DebugLogService._();
  DebugLogService._();

  static const maxEntries = 2000;

  /// [YYYY-MM-DD HH:MM:SS] message
  static final _linePatternNew = RegExp(
    r'^\[(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\] (.*)$',
  );

  final List<LogEntry> _entries = [];
  bool _enabled = false;
  bool _loaded = false;
  File? _logFile;

  static const _prefKey = 'debug_log_enabled';

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool(_prefKey, value),
      onError: (e) => debugPrint('[DebugLog] Failed to persist enabled: $e'),
    );
  }

  /// 主 Isolate 保存日志文件路径，供子 Isolate 使用
  static String? _logFilePath;

  /// 获取日志文件路径，供主 Isolate 传给子 Isolate
  String? get logFilePath => _logFilePath;

  /// 子 Isolate 写入后，主 Isolate 上次同步到的文件偏移量
  int _lastSyncedOffset = 0;

  /// 从原始日志消息中解析 tag 和 level（用于 LogEntry 构造）
  static (String?, String) parseTagAndLevel(String message) {
    String? tag;
    final tagMatch = RegExp(r'^\[([^\]]+)\]\s*').firstMatch(message);
    if (tagMatch != null) {
      tag = tagMatch.group(1);
    }
    final lower = message.toLowerCase();
    String level = 'info';
    if (lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('exception')) {
      level = 'error';
    } else if (lower.contains('skip') ||
        lower.contains('skipping') ||
        lower.contains('give up') ||
        lower.contains('warn')) {
      level = 'warning';
    }
    return (tag, level);
  }

  /// 新日志通知
  final ValueNotifier<int> logCount = ValueNotifier(0);

  /// 解析一行日志文本，支持新格式 [YYYY-MM-DD HH:MM:SS] 和旧格式 [HH:MM:SS]
  LogEntry? _parseLine(String line) {
    // 优先匹配新格式
    var match = _linePatternNew.firstMatch(line);
    if (match != null) {
      final time = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
      final msg = match.group(7)!;
      final (tag, level) = parseTagAndLevel(msg);
      return LogEntry(time, msg, tag: tag, level: level);
    }
    return null;
  }

  /// 为子 Isolate 设置 debugPrint 拦截
  ///
  /// 在 `Isolate.run()` 回调的开头调用
  /// [logFilePath] 由主 Isolate 传入（Dart Isolate 不共享静态变量）
  /// 子 Isolate 无法使用平台通道获取文档目录，因此通过主 Isolate
  /// 传递的路径直接写文件
  static void setupIsolateLogging({String? logFilePath}) {
    final path = logFilePath ?? _logFilePath;
    if (path == null) return;
    final file = File(path);

    debugPrint = (String? message, {int? wrapWidth}) {
      final msg = message ?? '';
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final mo = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      final s = now.second.toString().padLeft(2, '0');
      try {
        file.writeAsStringSync(
          '[$y-$mo-$d $h:$m:$s] $msg\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    };
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      // 恢复 debug mode 开关状态
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? false;

      final dir = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(dir.path, 'debug_log.txt'));
      _logFilePath = _logFile!.path;
      if (await _logFile!.exists()) {
        final lines = await _logFile!.readAsLines();
        for (final line in lines) {
          final entry = _parseLine(line);
          if (entry != null) {
            _entries.add(entry);
          }
        }
        // 超过上限时截断旧日志
        while (_entries.length > maxEntries) {
          _entries.removeAt(0);
        }
        logCount.value = _entries.length;
      }
      // 记录初始文件偏移量，后续增量同步
      try {
        if (_logFile != null && await _logFile!.exists()) {
          _lastSyncedOffset = await _logFile!.length();
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[DebugLog] Failed to load log file: $e');
    }
  }

  void add(String message) {
    if (!enabled) return;

    final (tag, level) = parseTagAndLevel(message);
    final entry = LogEntry(DateTime.now(), message, tag: tag, level: level);
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    logCount.value = _entries.length;

    // 同步写入磁盘
    final bytesWritten = _writeLine(entry.toLine());
    // 主 Isolate 写入的行也更新偏移量，避免 syncNewEntriesFromDisk 重复读取
    _lastSyncedOffset += bytesWritten;
  }

  /// 同步追加一行到日志文件，返回写入的字节数
  int _writeLine(String line) {
    try {
      if (_logFile != null) {
        final data = '$line\n';
        _logFile!.writeAsStringSync(data, mode: FileMode.append, flush: true);
        return data.length;
      }
    } catch (_) {}
    return 0;
  }

  /// 从磁盘增量读取子 Isolate 写入的新日志，追加到内存列表
  ///
  /// 由 UI 层定期调用（如 Timer.periodic），确保子 Isolate 写入文件的
  /// 日本能实时显示在 Debug Log Manager 中
  Future<void> syncNewEntriesFromDisk() async {
    if (_logFile == null || !enabled) return;
    try {
      if (!await _logFile!.exists()) return;
      final size = await _logFile!.length();
      if (size <= _lastSyncedOffset) return;

      // 读取新增部分
      final raf = await _logFile!.open(mode: FileMode.read);
      await raf.setPosition(_lastSyncedOffset);
      final newBytes = await raf.read(size - _lastSyncedOffset);
      await raf.close();

      final newContent = utf8.decode(newBytes);
      final lines = newContent.split('\n');
      bool added = false;
      for (final line in lines) {
        if (line.isEmpty) continue;
        final entry = _parseLine(line);
        if (entry != null) {
          _entries.add(entry);
          added = true;
        }
      }
      _lastSyncedOffset = size;

      // 超过上限时截断旧日志
      while (_entries.length > maxEntries) {
        _entries.removeAt(0);
      }
      if (added) logCount.value = _entries.length;
    } catch (_) {}
  }

  Future<void> clear() async {
    _entries.clear();
    _lastSyncedOffset = 0;
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

    final buf = StringBuffer();
    // 运行环境信息
    buf.writeln(await _collectPlatformInfo());
    buf.writeln();
    // 日志内容
    for (final e in _entries) {
      buf.writeln(e.toLine());
    }
    return file.writeAsString(buf.toString());
  }

  /// 导出为 JSON 格式，返回临时文件
  Future<File> exportToJson() async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File(p.join(dir.path, 'e4pix_log_$ts.json'));

    final platformInfo = await _collectPlatformInfoRaw();
    final entriesList = _entries.map((e) {
      final t = e.time;
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      final s = t.second.toString().padLeft(2, '0');
      return {
        'time':
            '${t.year}-${t.month.toString().padLeft(2, '0')}-'
            '${t.day.toString().padLeft(2, '0')} $h:$m:$s',
        if (e.tag != null) 'tag': e.tag,
        'message': e.message,
        'level': e.level,
      };
    }).toList();

    final jsonMap = {
      'platform': platformInfo,
      'exportedAt': now.toIso8601String(),
      'entries': entriesList,
    };

    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }

  /// 返回原始平台信息 Map（供 JSON 导出用）
  Future<Map<String, String>> _collectPlatformInfoRaw() async {
    final info = <String, String>{
      'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'locale': Platform.localeName,
      'cpus': '${Platform.numberOfProcessors}',
      'dart': Platform.version,
    };
    final device = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final d = await device.androidInfo;
        info['device'] =
            'Android ${d.version.sdkInt} (${d.version.release}) ${d.manufacturer} ${d.model}';
      } else if (Platform.isWindows) {
        final d = await device.windowsInfo;
        info['device'] =
            'Windows ${d.majorVersion}.${d.minorVersion} build ${d.buildNumber} (${d.computerName})';
      } else if (Platform.isMacOS) {
        final d = await device.macOsInfo;
        info['device'] = 'macOS ${d.osRelease}';
      } else if (Platform.isLinux) {
        final d = await device.linuxInfo;
        info['device'] = 'Linux ${d.prettyName}';
      } else if (Platform.isIOS) {
        final d = await device.iosInfo;
        info['device'] = 'iOS ${d.systemVersion} (${d.utsname.machine})';
      }
    } catch (_) {}
    return info;
  }

  Future<String> _collectPlatformInfo() async {
    final buf = StringBuffer();
    buf.writeln('═══ e4pix log export ═══');
    buf.writeln(
      '[Platform] OS: ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}',
    );
    buf.writeln('[Platform] Locale: ${Platform.localeName}');
    buf.writeln('[Platform] CPUs: ${Platform.numberOfProcessors}');
    buf.writeln('[Platform] Dart: ${Platform.version}');

    final device = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await device.androidInfo;
        buf.writeln(
          '[Device] Android ${info.version.sdkInt} '
          '(${info.version.release})',
        );
        buf.writeln('[Device] ${info.manufacturer} ${info.model}');
        buf.writeln('[Device] ABI: ${info.supportedAbis.join(", ")}');
      } else if (Platform.isWindows) {
        final info = await device.windowsInfo;
        buf.writeln(
          '[Device] Windows ${info.majorVersion}.${info.minorVersion} '
          'build ${info.buildNumber}',
        );
        buf.writeln('[Device] ${info.computerName}');
        buf.writeln('[Device] CPUs: ${info.numberOfCores}');
      } else if (Platform.isMacOS) {
        final info = await device.macOsInfo;
        buf.writeln('[Device] macOS ${info.osRelease}');
      } else if (Platform.isLinux) {
        final info = await device.linuxInfo;
        buf.writeln('[Device] Linux ${info.prettyName}');
      } else if (Platform.isIOS) {
        final info = await device.iosInfo;
        buf.writeln(
          '[Device] iOS ${info.systemVersion} '
          '(${info.utsname.machine})',
        );
      }
    } catch (e) {
      buf.writeln('[Device] Failed to get device info: $e');
    }
    buf.writeln('═══════════════════════');
    return buf.toString();
  }
}
