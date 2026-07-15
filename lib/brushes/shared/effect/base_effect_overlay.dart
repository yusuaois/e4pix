import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/crop_params.dart';
import '../../../state/providers.dart';
import '../../../utils/brush_coord_utils.dart';
import '../../../utils/single_pointer_gesture_detector.dart';
import 'base_effect_painter.dart';
import 'effect_gesture_handler.dart';

/// 效果画笔 Overlay State 基类
///
/// 统一管理光标状态、[EffectGestureHandler] 手势委托、
/// MouseRegion + GestureDetector + CustomPaint 标准布局
///
/// 子类提供：Widget getter、画笔配置、回调
abstract class BaseEffectOverlayState<W extends ConsumerStatefulWidget>
    extends ConsumerState<W> {
  // Widget 属性

  Size get imageDisplaySize;
  CropParams get crop;
  int get sourceWidth;
  int get sourceHeight;

  // 画笔配置

  /// 归一化笔刷半径
  double get brushNorm;

  /// 笔刷硬度
  double get hardness;

  /// 光标环颜色
  Color get cursorColor;

  /// 是否激活
  bool get isActive;

  // 回调（子类对接 Riverpod notifier）

  /// 添加单个标记
  void onAddMarkAt(Offset target, double radius, double hardness);

  /// 批量提交标记
  void onAddStrokesBatch(List<Offset> targets, double radius, double hardness);

  // 内部状态

  Offset? _cursorPos;
  bool _isHovering = false;
  late final EffectGestureHandler _gestureHandler;

  @override
  void initState() {
    super.initState();
    _gestureHandler = EffectGestureHandler(
      onAddMark: onAddMarkAt,
      onAddStroke: onAddStrokesBatch,
    );
  }

  /// 暴露笔画点供子类定制
  @protected
  EffectGestureHandler get gestureHandler => _gestureHandler;

  // 坐标变换

  Offset _screenToSourceNorm(Offset screen) {
    return screenToSourceNorm(
      screen: screen,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  // 手势处理

  void _onTapDown(Offset localPosition) {
    _cursorPos = localPosition;
    _isHovering = true;
    final target = _screenToSourceNorm(localPosition);
    _gestureHandler.tap(target, brushNorm, hardness);
  }

  void _onPanStart(DragStartDetails details) {
    _cursorPos = details.localPosition;
    _isHovering = true;
    final pos = _screenToSourceNorm(details.localPosition);
    _gestureHandler.panStart(pos);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _cursorPos = details.localPosition;
    final pos = _screenToSourceNorm(details.localPosition);
    _gestureHandler.panUpdate(pos);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details) {
    _isHovering = false;
    _gestureHandler.panEnd(brushNorm, hardness);
    setState(() {});
  }

  void _onPanCancel() {
    _gestureHandler.panCancel();
    setState(() {});
  }

  // Build

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      onHover: (e) => setState(() {
        _isHovering = true;
        _cursorPos = e.localPosition;
      }),
      child: SinglePointerGestureDetector(
        onTapDown: (d) => _onTapDown(d.localPosition),
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: buildPainter(),
      ),
    );
  }

  /// 覆写以定制 Painter，默认构建 [BaseEffectPainter]
  @protected
  Widget buildPainter() {
    final zoomScale = ref.watch(zoomScaleProvider);
    return CustomPaint(
      size: imageDisplaySize,
      painter: BaseEffectPainter(
        strokePoints: _gestureHandler.strokePoints,
        isPainting: _gestureHandler.isPainting,
        cursorPos: _cursorPos,
        isHovering: _isHovering,
        brushNorm: brushNorm,
        zoomScale: zoomScale,
        cursorColor: cursorColor,
        imageDisplaySize: imageDisplaySize,
        crop: crop,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      ),
    );
  }
}
