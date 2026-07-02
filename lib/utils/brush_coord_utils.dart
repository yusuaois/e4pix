import 'dart:ui';

import '../core/models/crop_params.dart';

/// 屏幕坐标（相对 imageDisplaySize）→ 归一化源图坐标 [0..1]
///
/// 将用户在 overlay 上的点击/拖拽位置转换为全图坐标系的坐标，
/// 供污点修复、修复画笔等工具的 spot 标记使用
///
/// 内部调用 [CropParams.outputToSourceNorm] 处理裁剪/旋转/翻转变换
///
/// [screen] 相对 [imageDisplaySize] 的像素坐标
/// [imageDisplaySize] 显示区域尺寸
/// [crop] 当前裁剪参数
/// [sourceWidth]/[sourceHeight] 原始全图尺寸（像素）
Offset screenToSourceNorm({
  required Offset screen,
  required Size imageDisplaySize,
  required CropParams crop,
  required int sourceWidth,
  required int sourceHeight,
}) {
  final nx = (screen.dx / imageDisplaySize.width).clamp(0.0, 1.0);
  final ny = (screen.dy / imageDisplaySize.height).clamp(0.0, 1.0);
  final (sx, sy) = crop.outputToSourceNorm(nx, ny, sourceWidth, sourceHeight);
  return Offset(sx, sy);
}

/// 归一化源图坐标 [0..1] → 屏幕坐标（相对 imageDisplaySize）
///
/// [screenToSourceNorm] 的逆变换,用于将 cloneSource 等全图坐标映射回
/// 屏幕显示位置（如源点十字线、cloneSource 指示器）
///
/// [src] 全图归一化坐标 [0..1]
/// [imageDisplaySize] 显示区域尺寸
/// [crop] 当前裁剪参数
/// [sourceWidth]/[sourceHeight] 原始全图尺寸（像素）
Offset sourceToScreenNorm({
  required Offset src,
  required Size imageDisplaySize,
  required CropParams crop,
  required int sourceWidth,
  required int sourceHeight,
}) {
  final (ox, oy) = crop.forwardToOutputNorm(
    src.dx,
    src.dy,
    sourceWidth,
    sourceHeight,
  );
  return Offset(ox * imageDisplaySize.width, oy * imageDisplaySize.height);
}

/// 源图归一化半径 → 屏幕像素半径
///
/// 通过计算源点 x 方向偏移 [r] 后的屏幕位置差来得到屏幕像素半径，
/// 正确处理裁剪/旋转带来的各向异性缩放
///
/// [r] 全图归一化半径（相对于源图宽度）
/// [srcCenter] 源点中心的全图归一化坐标
/// [imageDisplaySize] 显示区域尺寸
/// [crop] 当前裁剪参数
/// [sourceWidth]/[sourceHeight] 原始全图尺寸（像素）
double sourceRadiusToScreen({
  required double r,
  required Offset srcCenter,
  required Size imageDisplaySize,
  required CropParams crop,
  required int sourceWidth,
  required int sourceHeight,
}) {
  final (ox0, _) = crop.forwardToOutputNorm(
    srcCenter.dx,
    srcCenter.dy,
    sourceWidth,
    sourceHeight,
  );
  final (ox1, _) = crop.forwardToOutputNorm(
    srcCenter.dx + r,
    srcCenter.dy,
    sourceWidth,
    sourceHeight,
  );
  return (ox1 - ox0).abs() * imageDisplaySize.width;
}
