import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:easy_localization/easy_localization.dart';

/// 联机拍摄与文件夹监听常驻通知服务
class TetherNotificationService {
  TetherNotificationService._();
  static final instance = TetherNotificationService._();

  final _androidPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // 固定 ID，确保原地刷新
  static const int _cameraNotificationId = 2001;
  static const int _watcherNotificationId = 2002;

  LocalNotification? _windowsCameraNotification;
  LocalNotification? _windowsWatcherNotification;

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      const androidSettings = AndroidInitializationSettings(
        '@drawable/ic_launcher_foreground',
      );
      const settings = InitializationSettings(android: androidSettings);
      await _androidPlugin.initialize(settings);
    } else if (Platform.isWindows) {
      await localNotifier.setup(
        appName: 'e4pix',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    }

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
    if (!Platform.isAndroid && !Platform.isWindows) return;
    await _ensureInit();

    final title = tr('tetherCameraNotificationTitle');
    final body = '$model (${tr('saveTo')}: $saveFolder)';

    if (Platform.isAndroid) {
      await _androidPlugin.show(
        _cameraNotificationId,
        title,
        body,
        _androidOngoingChannel('e4pix_camera_tether', 'Camera Tethering'),
      );
    } else if (Platform.isWindows) {
      await dismissCameraOngoing();
      _windowsCameraNotification = LocalNotification(title: title, body: body);

      _windowsCameraNotification?.onClick = () {
        Process.run('explorer.exe', [saveFolder]);
      };

      await _windowsCameraNotification?.show();
    }
  }

  /// 消除 相机联机通知
  Future<void> dismissCameraOngoing() async {
    if (Platform.isAndroid) {
      await _androidPlugin.cancel(_cameraNotificationId);
    } else if (Platform.isWindows) {
      await _windowsCameraNotification?.close();
      _windowsCameraNotification = null;
    }
  }

  // ==================== 文件夹监听通知 ====================

  /// 显示/更新 文件夹监听常驻通知
  Future<void> showWatcherOngoing({required String watchPath}) async {
    if (!Platform.isAndroid && !Platform.isWindows) return;
    await _ensureInit();

    final title = tr('tetherWatcherNotificationTitle');
    final body = watchPath;

    if (Platform.isAndroid) {
      await _androidPlugin.show(
        _watcherNotificationId,
        title,
        body,
        _androidOngoingChannel('e4pix_folder_watcher', 'Folder Watcher'),
      );
    } else if (Platform.isWindows) {
      await dismissWatcherOngoing();
      _windowsWatcherNotification = LocalNotification(title: title, body: body);

      _windowsWatcherNotification?.onClick = () {
        Process.run('explorer.exe', [watchPath]);
      };

      await _windowsWatcherNotification?.show();
    }
  }

  /// 消除 文件夹监听通知
  Future<void> dismissWatcherOngoing() async {
    if (Platform.isAndroid) {
      await _androidPlugin.cancel(_watcherNotificationId);
    } else if (Platform.isWindows) {
      await _windowsWatcherNotification?.close();
      _windowsWatcherNotification = null;
    }
  }

  // —— 内部工具 ——

  /// 配置 Android 常驻通知通道
  NotificationDetails _androidOngoingChannel(
    String channelId,
    String channelName,
  ) => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'e4pix active tethering session status',
      importance: Importance.low, // 通知重要性低 隐藏通知
      priority: Priority.low,
      ongoing: true, // 常驻通知
      autoCancel: false, // 点击通知不会自动消失
      icon: '@drawable/ic_launcher_foreground',
    ),
  );
}
