import 'package:flutter/material.dart';

/// 仅响应单指手势的 GestureDetector。
/// 当触点数 >= 2 时，忽略单指手势，将事件穿透给父级（如 InteractiveViewer）处理捏合缩放。
class SinglePointerGestureDetector extends StatefulWidget {
  const SinglePointerGestureDetector({
    super.key,
    required this.child,
    this.onTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.behavior = HitTestBehavior.translucent,
  });

  final Widget child;
  final GestureTapDownCallback? onTapDown;
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
  int _pointerCount = 0;

  void _updatePointerCount(int delta) {
    setState(() {
      _pointerCount += delta;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMultiPointer = _pointerCount >= 2;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (_pointerCount == 1) {
          widget.onPanCancel?.call();
        }
        _updatePointerCount(1);
      },
      onPointerUp: (_) => _updatePointerCount(-1),
      onPointerCancel: (_) => _updatePointerCount(-1),
      child: IgnorePointer(
        ignoring: isMultiPointer,
        child: GestureDetector(
          behavior: widget.behavior,
          onTapDown: widget.onTapDown,
          onPanStart: widget.onPanStart,
          onPanUpdate: widget.onPanUpdate,
          onPanEnd: widget.onPanEnd,
          onPanCancel: widget.onPanCancel,
          child: widget.child,
        ),
      ),
    );
  }
}
