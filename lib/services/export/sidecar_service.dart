import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../brushes/brush_manifest.dart';
import '../../brushes/shared/stamp/stamp_mark.dart';
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
      final paramsJson = j['params'] as Map<String, dynamic>?;
      final params = paramsJson != null
          ? AdjustmentParams.fromJson(
              paramsJson,
              brushMarks: _parseBrushMarks(paramsJson['brushMarks']),
            )
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

  /// 从 JSON 反序列化 brushMarks map
  static Map<String, List<StampMark>>? _parseBrushMarks(dynamic raw) {
    if (raw == null || raw is! Map) return null;
    final result = <String, List<StampMark>>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! List) continue;
      final manifest = brushManifests.cast<BrushManifest?>().firstWhere(
        (m) => m?.id == entry.key,
        orElse: () => null,
      );
      if (manifest?.marksFromJson == null) continue;
      final jsonList = (entry.value as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (jsonList.isEmpty) continue;
      result[entry.key as String] = manifest!.marksFromJson!(jsonList);
    }
    return result;
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
