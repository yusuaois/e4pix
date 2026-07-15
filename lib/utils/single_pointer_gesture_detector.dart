import 'package:flutter/material.dart';

/// 单指时等价于普通 GestureDetector；
/// 双指时替换为 IgnorePointer，使父级 InteractiveViewer 的
/// ScaleGestureRecognizer 无竞争地赢得 arena 以接管捏合缩放
class SinglePointerGestureDetector extends StatefulWidget {
  const SinglePointerGestureDetector({
    super.key,
    required this.child,
    this.onTapDown,
    this.onTapUp,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.behavior = HitTestBehavior.translucent,
  });

  final Widget child;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onPanCancel;
  final HitTestBehavior behavior;

  @override
  State<SinglePointerGestureDetector> createState() =>
      _SinglePointerGestureDetectorState();
}

class _SinglePointerGestureDetectorState
    extends State<SinglePointerGestureDetector> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_count == 1) widget.onPanCancel?.call(); // 第二指 → 取消笔触
        setState(() => _count++);
      },
      onPointerUp: (_) {
        if (_count > 0) setState(() => _count--);
      },
      onPointerCancel: (_) {
        if (_count > 0) setState(() => _count--);
      },
      child: _count >= 2
          ? IgnorePointer(child: widget.child)
          : GestureDetector(
              behavior: widget.behavior,
              onTapDown: widget.onTapDown,
              onTapUp: widget.onTapUp,
              onPanStart: widget.onPanStart,
              onPanUpdate: widget.onPanUpdate,
              onPanEnd: widget.onPanEnd,
              onPanCancel: widget.onPanCancel,
              child: widget.child,
            ),
    );
  }
}
