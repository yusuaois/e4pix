import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_info.dart';

class UpdateAsset {
  final String name;
  final String url;
  final int size;
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
  });
}

class UpdateInfo {
  final String latestVersion; // 2.6.3
  final String tagName; // v2.6.3
  final String releaseUrl;
  final String body;
  final List<UpdateAsset> assets;
  final bool hasUpdate;

  const UpdateInfo({
    required this.latestVersion,
    required this.tagName,
    required this.releaseUrl,
    required this.body,
    required this.assets,
    required this.hasUpdate,
  });

  /// 选出适配当前平台的下载资源。
  ///
  /// Android：分架构发布（arm64-v8a / armeabi-v7a / x86_64 / universal）。
  /// 按设备支持的 ABI 优先级选对应 apk，找不到则回退 universal（文件名不含 ABI 关键词）。
  /// 异步：需要查询设备 ABI。
  Future<UpdateAsset?> assetForPlatform() async {
    if (Platform.isAndroid) {
      return _androidApk();
    }
    String? kw;
    if (Platform.isWindows) {
      kw = 'windows';
    } else if (Platform.isMacOS) {
      kw = 'macos';
    } else if (Platform.isLinux) {
      kw = 'linux';
    }
    if (kw == null) return null;
    for (final a in assets) {
      if (a.name.toLowerCase().contains(kw)) return a;
    }
    return null;
  }

  Future<UpdateAsset?> _androidApk() async {
    // 设备支持的 ABI，按优先级（首个为主 ABI）
    List<String> abis = const [];
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      abis = info.supportedAbis;
    } catch (_) {}

    // 1) 按设备 ABI 优先级找对应 apk（arm64 设备优先 arm64 包）
    for (final abi in abis) {
      final key = abi.toLowerCase(); // arm64-v8a / armeabi-v7a / x86_64
      for (final a in assets) {
        final n = a.name.toLowerCase();
        if (n.endsWith('.apk') && n.contains(key)) {
          return a;
        }
      }
    }

    // 2) 回退 universal：apk 且不含任何 ABI 关键词
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (n.endsWith('.apk') &&
          !n.contains('arm64') &&
          !n.contains('armeabi') &&
          !n.contains('v7a') &&
          !n.contains('x86')) {
        return a;
      }
    }

    // 3) 兜底：任意 apk
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith('.apk')) return a;
    }
    return null;
  }
}

class UpdateService {
  static const _ignoredKey = 'update_ignored_version';

  static Future<void> ignoreVersion(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_ignoredKey, v);
  }

  static Future<String?> ignoredVersion() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_ignoredKey);
  }

  static Future<UpdateInfo?> check() async {
    final resp = await http.get(
      Uri.parse(AppInfo.latestReleaseApi),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (resp.statusCode != 200) return null;

    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (latest.isEmpty) return null;

    final info = await PackageInfo.fromPlatform();
    final current = info.version; // 如 2.6.3

    final assets = <UpdateAsset>[];
    for (final a in (json['assets'] as List? ?? [])) {
      final m = a as Map<String, dynamic>;
      assets.add(
        UpdateAsset(
          name: (m['name'] as String?) ?? '',
          url: (m['browser_download_url'] as String?) ?? '',
          size: (m['size'] as int?) ?? 0,
        ),
      );
    }

    final rawBody = (json['body'] as String?) ?? '';
    final sepIdx = rawBody.indexOf('---');
    final body = sepIdx >= 0
        ? rawBody.substring(0, sepIdx).trimRight()
        : rawBody.trimRight();

    return UpdateInfo(
      latestVersion: latest,
      tagName: tag,
      releaseUrl: (json['html_url'] as String?) ?? '',
      body: body,
      assets: assets,
      hasUpdate: _isNewer(latest, current),
    );
  }

  static bool _isNewer(String a, String b) {
    List<int> parse(String v) {
      final core = v.split('+').first.split('-').first;
      return core.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    }

    final pa = parse(a), pb = parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
