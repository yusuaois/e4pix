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

    await ExportNotificationService.instance.init();
    await TetherNotificationService.instance.init();

    _initialized = true;
  }
}