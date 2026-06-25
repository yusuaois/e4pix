import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/tethered_shot.dart';

/// 每张 RAW 旁的编辑 sidecar：rawpath.e4pix.json
class SidecarService {
  SidecarService._();

  static const _ext = '.e4pix.json';
  static const _version = 1;

  static String sidecarPath(String rawPath) => '$rawPath$_ext';

  /// 读取 sidecar，返回 (params, rating, flag)；不存在/失败返回 null
  static Future<SidecarData?> read(String rawPath) async {
    try {
      final f = File(sidecarPath(rawPath));
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final params = j['params'] != null
          ? AdjustmentParams.fromJson(j['params'] as Map<String, dynamic>)
          : AdjustmentParams.neutral;
      final rating = (j['rating'] as num?)?.toInt() ?? 0;
      final flag = _flagFromString(j['flag'] as String?);
      return SidecarData(params: params, rating: rating, flag: flag);
    } catch (e) {
      debugPrint('[Sidecar] Failed to read $rawPath: $e');
      return null;
    }
  }

  /// 写 sidecar 只读位置/失败 → 静默返回 false
  static Future<bool> write(
    String rawPath, {
    required AdjustmentParams params,
    required int rating,
    required ShotFlag flag,
  }) async {
    try {
      // 全默认→ 不写
      if (params == AdjustmentParams.neutral &&
          rating == 0 &&
          flag == ShotFlag.none) {
        // 若已有 sidecar 但现在重置回默认，删掉
        final f = File(sidecarPath(rawPath));
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (e) {
            debugPrint('[Sidecar] Failed to delete $rawPath: $e');
          }
        }
        return true;
      }
      final j = {
        'version': _version,
        'params': params.toJson(),
        'rating': rating,
        'flag': _flagToString(flag),
        'savedAt': DateTime.now().toIso8601String(),
      };
      final f = File(sidecarPath(rawPath));
      await f.writeAsString(jsonEncode(j), flush: true);
      return true;
    } catch (e) {
      debugPrint('[Sidecar] Failed to write $rawPath: $e');
      return false;
    }
  }

  static String _flagToString(ShotFlag f) => switch (f) {
    ShotFlag.pick => 'pick',
    ShotFlag.reject => 'reject',
    ShotFlag.none => 'none',
  };
  static ShotFlag _flagFromString(String? s) => switch (s) {
    'pick' => ShotFlag.pick,
    'reject' => ShotFlag.reject,
    _ => ShotFlag.none,
  };
}

class SidecarData {
  final AdjustmentParams params;
  final int rating;
  final ShotFlag flag;
  const SidecarData({
    required this.params,
    required this.rating,
    required this.flag,
  });
}
