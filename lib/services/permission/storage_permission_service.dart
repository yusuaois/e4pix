import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 存储权限服务
///
/// e4pix 经 FFI(LibRaw) 按路径解码 RAW，Android 13+ 作用域存储下需
/// 「所有文件访问」权限；仅 READ_MEDIA_IMAGES 覆盖不到 RAW 文件
/// （Directory.list() 会将其过滤为空）
class StoragePermissionService {
  StoragePermissionService._();

  /// 是否已授予「所有文件访问」（非 Android 视为已授予）
  static Future<bool> isAllFilesAccessGranted() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.manageExternalStorage.status).isGranted;
  }

  /// 请求「所有文件访问」：未授权则打开系统设置页，等待用户返回
  static Future<bool> requestAllFilesAccess() async {
    if (await isAllFilesAccessGranted()) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }
}
