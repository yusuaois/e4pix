import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:easy_localization/easy_localization.dart';

/// 导出完成/失败通知
class ExportNotificationService {
  ExportNotificationService._();
  static final instance = ExportNotificationService._();

  // Android 插件实例
  final _androidPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _idCounter = 0;

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 初始化通知服务
  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      // --- Android 初始化 ---
      const androidSettings = AndroidInitializationSettings(
        '@drawable/ic_launcher_foreground',
      );
      const settings = InitializationSettings(android: androidSettings);
      await _androidPlugin.initialize(settings);

      // Android 13+ 运行时申请通知权限
      await _androidPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (_isDesktop) {
      // --- 桌面平台初始化 ---
      await localNotifier.setup(
        appName: 'e4pix',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    }

    _initialized = true;
  }

  /// 单张导出完成
  Future<void> notifyDone({
    required String filename,
    required String outputPath,
  }) async {
    if (!Platform.isAndroid && !_isDesktop) return;
    await _ensureInit();

    final title = tr('exportNotifyDoneTitle');
    final body = filename;

    if (Platform.isAndroid) {
      await _androidPlugin.show(_nextId(), title, body, _androidChannel());
    } else if (_isDesktop) {
      _showDesktopToast(title: title, body: body, outputDir: outputPath);
    }
  }

  /// 批量导出全部完成
  Future<void> notifyBatchDone({
    required int count,
    required String outputDir,
  }) async {
    if (!Platform.isAndroid && !_isDesktop) return;
    await _ensureInit();

    final title = tr('exportNotifyBatchDoneTitle');
    final body = tr('exportNotifyBatchDoneBody', args: ['$count']);

    if (Platform.isAndroid) {
      await _androidPlugin.show(_nextId(), title, body, _androidChannel());
    } else if (_isDesktop) {
      _showDesktopToast(title: title, body: body, outputDir: outputDir);
    }
  }

  /// 单张导出失败
  Future<void> notifyFailed({
    required String filename,
    required String error,
    required String outputDir,
  }) async {
    if (!Platform.isAndroid && !_isDesktop) return;
    await _ensureInit();

    final title = tr('exportNotifyFailedTitle');
    final body = filename;

    if (Platform.isAndroid) {
      await _androidPlugin.show(_nextId(), title, body, _androidChannel());
    } else if (_isDesktop) {
      _showDesktopToast(title: title, body: body, outputDir: outputDir);
    }
  }

  // —— 内部工具 ——

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  int _nextId() => ++_idCounter;

  /// Android 通知通道细节
  NotificationDetails _androidChannel() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'e4pix_export',
      'Export',
      channelDescription: 'e4pix export results',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_launcher_foreground',
    ),
  );

  /// 桌面 Toast 通知统一发送方法
  void _showDesktopToast({
    required String title,
    required String body,
    required String outputDir,
  }) {
    final notification = LocalNotification(title: title, body: body);
    notification.onClick = () {
      _openFolder(outputDir);
    };
    notification.show();
  }

  /// 在文件管理器中打开文件夹
  void _openFolder(String path) {
    if (Platform.isWindows) {
      Process.run('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
    }
  }
}
