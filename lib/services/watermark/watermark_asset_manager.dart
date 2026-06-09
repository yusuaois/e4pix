import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自定义水印资源管理器
///
/// 管理 `e4pix/custom_watermarks/` 目录下的用户自定义图片。
/// 支持 png / webp / jpg 格式。
class WatermarkAssetManager {
  WatermarkAssetManager._();

  static String? _dir;

  /// 获取或创建自定义水印资源目录
  static Future<String> get dir async {
    if (_dir != null) return _dir!;
    final appDir = await getApplicationDocumentsDirectory();
    _dir = p.join(appDir.path, 'e4pix', 'custom_watermarks');
    await Directory(_dir!).create(recursive: true);
    return _dir!;
  }

  /// 允许的图片扩展名
  static const _allowedExtensions = ['png', 'webp', 'jpg', 'jpeg'];

  /// 打开文件选择器并拷贝选中图片到水印目录。
  /// 返回目标路径（相对文件名），失败返回 null。
  static Future<String?> pickAndSaveCustomImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
      );
      if (result == null || result.files.isEmpty) return null;

      final srcPath = result.files.first.path;
      if (srcPath == null) return null;

      final srcFile = File(srcPath);
      if (!await srcFile.exists()) return null;

      final base = await dir;
      final ext = p.extension(srcPath);
      // 用时间戳 + 原文件名避免冲突
      final name = p.basenameWithoutExtension(srcPath);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final destName = '${name}_$stamp$ext';
      final destPath = p.join(base, destName);

      await srcFile.copy(destPath);
      return destName; // 仅返回文件名，目录由 dir 管理
    } catch (_) {
      return null;
    }
  }

  /// 列出所有自定义水印图片
  static Future<List<String>> listCustomImages() async {
    try {
      final base = await dir;
      final d = Directory(base);
      if (!await d.exists()) return [];
      final entries = await d.list().toList();
      return entries.whereType<File>().map((f) => p.basename(f.path)).where((
        name,
      ) {
        final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
        return _allowedExtensions.contains(ext);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 删除指定自定义图片
  static Future<bool> deleteCustomImage(String filename) async {
    try {
      final base = await dir;
      final file = File(p.join(base, filename));
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 解析图片路径 → 文件系统绝对路径
  static Future<String?> resolveFilePath(String filename) async {
    try {
      final base = await dir;
      final filePath = p.join(base, filename);
      final file = File(filePath);
      if (await file.exists()) return filePath;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 读取图片文件为字节
  static Future<Uint8List?> readImageBytes(String filename) async {
    try {
      final filePath = await resolveFilePath(filename);
      if (filePath == null) return null;
      return await File(filePath).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
