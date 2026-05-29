import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  UpdateAsset? get assetForPlatform {
    String? kw;
    if (Platform.isAndroid) {
      kw = '.apk';
    } else if (Platform.isWindows) {
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
}

class UpdateService {
  static const _owner = 'yusuaois';
  static const _repo = 'e4pix';
  static const _latestUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';
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
      Uri.parse(_latestUrl),
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

    return UpdateInfo(
      latestVersion: latest,
      tagName: tag,
      releaseUrl: (json['html_url'] as String?) ?? '',
      body: ((json['body'] as String?) ?? '')
          .substring(0, ((json['body'] as String?) ?? '').indexOf('---'))
          .trimRight(),
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
