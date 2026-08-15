import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 瓦片网格边长（源图像素）
const int kHiResGridTileEdge = 512;

/// 网格瓦片标识：金字塔层级 + 列/行索引
@immutable
class HiResTileId {
  final int level;
  final int col;
  final int row;
  const HiResTileId({this.level = 0, required this.col, required this.row});

  @override
  bool operator ==(Object other) =>
      other is HiResTileId &&
      other.level == level &&
      other.col == col &&
      other.row == row;

  @override
  int get hashCode => Object.hash(level, col, row);

  @override
  String toString() => 'HiResTileId($level,$col,$row)';
}

/// 把可见区域覆盖的网格单元切出，返回每块 src + displaySize 坐标 dst
///
/// 瓦片取完整整数网格单元（非小数交集），保证 1:1 精确提取、相邻瓦片 dst 严格连续
List<({HiResTileId id, Rect src, Rect dst})> computeGridTiles({
  required Rect visibleSrc,
  required Size fullOutSize,
  required Size displaySize,
  required int tileEdge,
  int level = 0,
}) {
  final fullW = fullOutSize.width;
  final fullH = fullOutSize.height;
  if (fullW <= 0 || fullH <= 0 || tileEdge <= 0 || visibleSrc.isEmpty) {
    return const [];
  }

  final scaleX = displaySize.width / fullW;
  final scaleY = displaySize.height / fullH;

  final numCols = (fullW / tileEdge).ceil();
  final numRows = (fullH / tileEdge).ceil();

  // 可见区域覆盖的网格索引范围（右/下边界减 ε 避免恰好压在网格线上时多取一格）
  const eps = 1e-6;
  final colStart = (visibleSrc.left / tileEdge).floor().clamp(0, numCols - 1);
  final colEnd = ((visibleSrc.right - eps) / tileEdge).floor().clamp(
    0,
    numCols - 1,
  );
  final rowStart = (visibleSrc.top / tileEdge).floor().clamp(0, numRows - 1);
  final rowEnd = ((visibleSrc.bottom - eps) / tileEdge).floor().clamp(
    0,
    numRows - 1,
  );

  final result = <({HiResTileId id, Rect src, Rect dst})>[];
  for (var row = rowStart; row <= rowEnd; row++) {
    final top = row * tileEdge.toDouble();
    final bottom = math.min((row + 1) * tileEdge.toDouble(), fullH);
    for (var col = colStart; col <= colEnd; col++) {
      final left = col * tileEdge.toDouble();
      final right = math.min((col + 1) * tileEdge.toDouble(), fullW);

      final src = Rect.fromLTRB(left, top, right, bottom);
      final dst = Rect.fromLTRB(
        src.left * scaleX,
        src.top * scaleY,
        src.right * scaleX,
        src.bottom * scaleY,
      );
      result.add((
        id: HiResTileId(level: level, col: col, row: row),
        src: src,
        dst: dst,
      ));
    }
  }
  return result;
}
