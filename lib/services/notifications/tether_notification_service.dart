import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';

/// 联机拍摄与文件夹监听常驻通知服务
class TetherNotificationService {
  TetherNotificationService._();
  static final instance = TetherNotificationService._();

  // FlutterLocalNotificationsPlugin
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // 固定 ID，确保原地刷新
  static const int _cameraNotificationId = 2001;
  static const int _watcherNotificationId = 2002;

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

    _initialized = true;
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  // ==================== 相机联机通知 ====================

  /// 显示/更新 相机联机常驻通知
  Future<void> showCameraOngoing({
    required String model,
    required String saveFolder,
  }) async {
    await _ensureInit();

    final title = tr('tetherCameraNotificationTitle');
    final body = '$model (${tr('saveTo')}: $saveFolder)';

    await _plugin.show(
      id: _cameraNotificationId,
      title: title,
      body: body,
      notificationDetails: _buildNotificationDetails(
        'e4pix_camera_tether',
        'Camera Tethering',
      ),
    );
  }

  /// 消除 相机联机通知
  Future<void> dismissCameraOngoing() async {
    await _plugin.cancel(id: _cameraNotificationId);
  }

  // ==================== 文件夹监听通知 ====================

  /// 显示/更新 文件夹监听常驻通知
  Future<void> showWatcherOngoing({required String watchPath}) async {
    await _ensureInit();

    final title = tr('tetherWatcherNotificationTitle');
    final body = watchPath;

    await _plugin.show(
      id: _watcherNotificationId,
      title: title,
      body: body,
      notificationDetails: _buildNotificationDetails(
        'e4pix_folder_watcher',
        'Folder Watcher',
      ),
    );
  }

  /// 消除 文件夹监听通知
  Future<void> dismissWatcherOngoing() async {
    await _plugin.cancel(id: _watcherNotificationId);
  }

  // —— 内部工具 ——
  /// 构建跨平台 NotificationDetails
  NotificationDetails _buildNotificationDetails(
    String channelId,
    String channelName,
  ) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'e4pix active tethering session status',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true, // 常驻通知
        autoCancel: false,
        icon: '@drawable/ic_launcher_foreground',
      ),
    );
  }
}
