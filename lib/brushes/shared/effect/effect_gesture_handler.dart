import 'package:flutter/material.dart';

import '../../../utils/path_brush_tracker.dart';

/// 效果画笔手势与笔画状态管理器
class EffectGestureHandler {
  EffectGestureHandler({required this.onAddMark, required this.onAddStroke});

  /// 点击添加单个标记
  final void Function(Offset target, double radius, double hardness) onAddMark;

  /// 笔画结束批量提交采样点
  final void Function(List<Offset> targets, double radius, double hardness)
  onAddStroke;

  PathBrushTracker? _tracker;
  final List<Offset> _strokePoints = [];

  /// 是否正在绘制
  bool get isPainting => _tracker != null;

  /// 当前笔画点快照
  List<Offset> get strokePoints => List<Offset>.from(_strokePoints);

  /// 点击放置单点
  void tap(Offset pos, double radius, double hardness) {
    onAddMark(pos, radius, hardness);
  }

  /// 开始新笔画
  void panStart(Offset pos) {
    _strokePoints.clear();
    _strokePoints.add(pos);
    _tracker = PathBrushTracker(spacing: 0.005);
    _tracker!.start(pos);
  }

  /// 延伸当前笔画
  void panUpdate(Offset pos) {
    final t = _tracker;
    if (t == null) return;
    for (final sampled in t.move(pos)) {
      _strokePoints.add(sampled);
    }
  }

  /// 结束笔画并提交
  void panEnd(double radius, double hardness) {
    final t = _tracker;
    if (t != null) {
      for (final sampled in t.end()) {
        _strokePoints.add(sampled);
      }
    }
    if (_strokePoints.isNotEmpty) {
      onAddStroke(List<Offset>.from(_strokePoints), radius, hardness);
    }
    _strokePoints.clear();
    _tracker = null;
  }

  /// 取消笔画并丢弃
  void panCancel() {
    _strokePoints.clear();
    _tracker = null;
  }
}
