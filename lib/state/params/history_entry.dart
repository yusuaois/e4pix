import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/adjustment_params.dart';

/// 一条历史记录条目
///
/// 包含参数快照、缩略图（120×80，惰性渲染）、时间戳和操作标签
@immutable
class HistoryEntry {
  final String id;
  final String label;
  final AdjustmentParams params;
  final DateTime timestamp;
  final ui.Image? thumbnail;

  const HistoryEntry({
    required this.id,
    required this.label,
    required this.params,
    required this.timestamp,
    this.thumbnail,
  });

  HistoryEntry copyWith({
    String? id,
    String? label,
    AdjustmentParams? params,
    DateTime? timestamp,
    ui.Image? thumbnail,
    bool clearThumbnail = false,
  }) => HistoryEntry(
    id: id ?? this.id,
    label: label ?? this.label,
    params: params ?? this.params,
    timestamp: timestamp ?? this.timestamp,
    thumbnail: clearThumbnail ? null : (thumbnail ?? this.thumbnail),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryEntry && id == other.id && timestamp == other.timestamp);

  @override
  int get hashCode => Object.hash(id, timestamp);
}
