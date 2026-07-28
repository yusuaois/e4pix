import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';

/// 导出完成/失败通知服务
class ExportNotificationService {
  ExportNotificationService._();
  static final instance = ExportNotificationService._();

  // FlutterLocalNotificationsPlugin
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _idCounter = 0;

  /// 初始化通知服务
  Future<void> init() async {
    if (_initialized) return;

    // 各平台初始化
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_launcher_foreground',
    );
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'e4pix',
      appUserModelId: 'com.yusuaois.e4pix',
      guid: '889f074a-463d-4c3e-8c85-618d360fbc35',
    );

    const settings = InitializationSettings(
      android: androidSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(settings: settings);

    // Android 13+ 运行时申请通知权限
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// 单张导出完成
  Future<void> notifyDone({
    required String filename,
    required String outputPath,
  }) async {
    await _ensureInit();

    await _plugin.show(
      id: _nextId(),
      title: tr('exportNotifyDoneTitle'),
      body: filename,
      notificationDetails: _buildNotificationDetails(),
    );
  }

  /// 批量导出全部完成
  Future<void> notifyBatchDone({
    required int count,
    required String outputDir,
  }) async {
    await _ensureInit();

    await _plugin.show(
      id: _nextId(),
      title: tr('exportNotifyBatchDoneTitle'),
      body: tr('exportNotifyBatchDoneBody', args: ['$count']),
      notificationDetails: _buildNotificationDetails(),
    );
  }

  /// 单张导出失败
  Future<void> notifyFailed({
    required String filename,
    required String error,
    required String outputDir,
  }) async {
    await _ensureInit();

    await _plugin.show(
      id: _nextId(),
      title: tr('exportNotifyFailedTitle'),
      body: filename,
      notificationDetails: _buildNotificationDetails(),
    );
  }

  // —— 内部工具 ——

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  int _nextId() => ++_idCounter;

  /// 构建跨平台 NotificationDetails
  NotificationDetails _buildNotificationDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      'e4pix_export',
      'Export',
      channelDescription: 'e4pix export results',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_launcher_foreground',
    ),
  );
}
