import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LensfunUpdateService {
  static const _versionKey = 'lensfun_db_sha';
  static const _owner = 'lensfun';
  static const _repo = 'lensfun';
  static const _dbPath = 'data/db';

  // ── 版本检查 ──────────────────────────────────────────────────────

  /// 返回 lensfun 仓库 data/db 路径的最新 commit SHA，失败返回 null
  static Future<String?> fetchLatestSha() async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/commits'
        '?path=$_dbPath&per_page=1',
      );
      debugPrint('[LensfunUpdate] GET $uri');
      final resp = await http.get(
        uri,
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) {
        debugPrint('[LensfunUpdate] API returned ${resp.statusCode}');
        return null;
      }
      final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
      if (list.isEmpty) {
        debugPrint('[LensfunUpdate] API returned empty list');
        return null;
      }
      final sha = list[0]['sha'] as String?;
      debugPrint('[LensfunUpdate] Latest SHA: $sha');
      return sha;
    } catch (e) {
      debugPrint('[LensfunUpdate] fetchLatestSha error: $e');
      return null;
    }
  }

  // ── 本地版本 ──────────────────────────────────────────────────────

  /// 返回已下载数据库的 SHA（来自 GitHub 更新），未更新过则返回 null
  static Future<String?> localSha() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_versionKey);
    } catch (e) {
      return null;
    }
  }

  // ── 下载 & 解压 ──────────────────────────────────────────────────

  /// 下载 zipball 并提取 XML 文件直接覆盖到 lensfun 目录
  /// 返回 true 表示成功
  static Future<bool> downloadAndExtract(String sha) async {
    try {
      // 1. 下载 zip
      final uri = Uri.parse(
        'https://github.com/$_owner/$_repo/archive/$sha.zip',
      );
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        debugPrint('[LensfunUpdate] Download returned ${resp.statusCode}');
        return false;
      }

      // 2. 解压，只提取 data/db/*.xml
      final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
      final xmlEntries = <String, List<int>>{}; // filename → bytes

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final parts = file.name.split('/');
        final dbIdx = parts.indexWhere((seg) => seg == 'data');
        if (dbIdx < 0 ||
            dbIdx + 1 >= parts.length ||
            parts[dbIdx + 1] != 'db') {
          continue;
        }
        final filename = parts.last;
        if (!filename.endsWith('.xml')) continue;
        final bytes = file.readBytes();
        if (bytes != null) {
          xmlEntries[filename] = bytes;
        }
      }

      if (xmlEntries.isEmpty) {
        debugPrint('[LensfunUpdate] No XML files found in zip');
        return false;
      }

      // 3. 直接覆盖写入 lensfun 目录
      final base = await getApplicationSupportDirectory();
      final targetDir = Directory(p.join(base.path, 'lensfun'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      for (final entry in xmlEntries.entries) {
        final outFile = File(p.join(targetDir.path, entry.key));
        await outFile.writeAsBytes(entry.value);
      }

      // 4. 持久化 SHA
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_versionKey, sha);

      debugPrint(
        '[LensfunUpdate] Updated to $sha (${xmlEntries.length} files)',
      );
      return true;
    } catch (e) {
      debugPrint('[LensfunUpdate] downloadAndExtract error: $e');
      return false;
    }
  }
}
