import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';

/// 一条历史记录条目
///
/// 包含参数快照、时间戳和操作标签
/// 缩略图由 [ThumbnailRenderer] 统一管理，通过 `history:$id` 键读取
@immutable
class HistoryEntry {
  final String id;
  final String label;
  final AdjustmentParams params;
  final DateTime timestamp;

  const HistoryEntry({
    required this.id,
    required this.label,
    required this.params,
    required this.timestamp,
  });

  HistoryEntry copyWith({
    String? id,
    String? label,
    AdjustmentParams? params,
    DateTime? timestamp,
  }) => HistoryEntry(
    id: id ?? this.id,
    label: label ?? this.label,
    params: params ?? this.params,
    timestamp: timestamp ?? this.timestamp,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryEntry && id == other.id && timestamp == other.timestamp);

  @override
  int get hashCode => Object.hash(id, timestamp);
}
