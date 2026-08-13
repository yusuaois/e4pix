import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知权限服务（Android 13+ 运行时申请）
class NotificationPermissionService {
  NotificationPermissionService._();

  /// 申请通知权限（系统弹窗，无自定义 UI）
  /// [plugin] 为已初始化的通知插件实例
  static Future<bool> requestNotificationPermission(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (!Platform.isAndroid) return true;
    final impl = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return (await impl?.requestNotificationsPermission()) ?? true;
  }
}
