import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 金字塔最小层级边长，逐级 ½ 降采样直到最小边 ≤ 该值
const double kHiResPyramidMinEdge = 256.0;

/// 层级质量系数：所选层级分辨率 ≥ 屏幕物理像素 × 该系数，=1.0 为无上采样阈值
const double kHiResPyramidOversample = 1.0;

/// 金字塔层级总数（含 L0）。L0 = 全尺寸，L1 = ½，L2 = ¼ …
int pyramidLevelCount(Size fullOutSize) {
  final minEdge = math.min(fullOutSize.width, fullOutSize.height);
  if (minEdge <= kHiResPyramidMinEdge) return 1;
  var count = 1;
  var edge = minEdge;
  while (edge / 2 >= kHiResPyramidMinEdge) {
    edge /= 2;
    count++;
  }
  return count;
}

/// 选当前 zoom 应用的金字塔层级（0=全尺寸，1=½…）
///
/// 所需 = displaySize × zoom × dpr × oversample，取最大的 k 使 fullOutSize/2^k ≥ 所需
int selectPyramidLevel({
  required double zoom,
  required double devicePixelRatio,
  required Size displaySize,
  required Size fullOutSize,
}) {
  final neededW =
      displaySize.width * zoom * devicePixelRatio * kHiResPyramidOversample;
  final neededH =
      displaySize.height * zoom * devicePixelRatio * kHiResPyramidOversample;

  final maxLevel = pyramidLevelCount(fullOutSize) - 1;
  var k = 0;
  while (k < maxLevel &&
      fullOutSize.width / (1 << (k + 1)) >= neededW &&
      fullOutSize.height / (1 << (k + 1)) >= neededH) {
    k++;
  }
  return k;
}
