import 'package:flutter/foundation.dart';

import 'export_notification_service.dart';
import 'tether_notification_service.dart';

/// 全局通知统一管理器
class NotificationManager {
  NotificationManager._();
  static final instance = NotificationManager._();

  bool _initialized = false;

  /// 全局初始化所有通知通道
  Future<void> init() async {
    if (_initialized) return;

    debugPrint('[Notification] Initializing...');
    try {
      await ExportNotificationService.instance.init();
      await TetherNotificationService.instance.init();
      debugPrint('[Notification] Initialized');
    } catch (e) {
      debugPrint('[Notification] Init failed: $e');
    }
    _initialized = true;
  }
}
