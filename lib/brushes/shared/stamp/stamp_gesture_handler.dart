import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/path_brush_tracker.dart';
import 'stamp_mark.dart';

/// 源-目标型画笔的手势与笔画状态管理器
///
/// 独立于 [State] 生命周期，通过构造函数注入所有依赖
/// 所有需要 [WidgetRef] 的方法接受 [ref] 参数
/// 通过回调与 [StampCompositor] 和持久化层通信
class StampGestureHandler<T extends StampMark> {
  StampGestureHandler({
    required this.createMark,
    required this.getBrushRadius,
    required this.getBrushHardness,
    required this.getCloneSource,
    required this.getIsSampling,
    required this.updateCloneSource,
    required this.addSingleMark,
    required this.commitMarksToPipeline,
    required this.computeCommittedHash,
    required this.renderedHashKey,
    required this.persistMarks,
    required this.screenToSource,
    required this.onNeedsSetState,
    required this.onStrokeStarted,
    required this.onTriggerComposite,
    this.onStrokeCommitted,
  });

  // --- 注入的 brush 配置读取 ---
  final T Function({
    required Offset source,
    required Offset target,
    required double radius,
    required double hardness,
    required DateTime createdAt,
  })
  createMark;

  final double Function(WidgetRef ref) getBrushRadius;
  final double Function(WidgetRef ref) getBrushHardness;
  final Offset? Function(WidgetRef ref) getCloneSource;
  final bool Function(WidgetRef ref) getIsSampling;

  // --- 注入的动作 ---
  final void Function(WidgetRef ref, Offset source) updateCloneSource;
  final void Function(WidgetRef ref, Offset target) addSingleMark;
  final void Function(WidgetRef ref, List<T> marks) commitMarksToPipeline;
  final int Function(WidgetRef ref) computeCommittedHash;

  // --- 注入的标识 ---
  final String renderedHashKey;

  // --- 注入的持久化 ---
  final void Function(
    WidgetRef ref,
    String key,
    List<StampMark> marks,
    int hash,
  )
  persistMarks;

  // --- 注入的工具函数 ---
  final Offset Function(Offset screen) screenToSource;

  // --- 注入的回调 ---
  final VoidCallback onNeedsSetState;
  final VoidCallback onStrokeStarted;
  final void Function({bool force}) onTriggerComposite;

  /// 笔画提交完成回调（用于 history panel 等外部监听）
  final VoidCallback? onStrokeCommitted;

  // --- 笔画状态 ---
  PathBrushTracker? strokeTracker;
  Offset? paintOffset;
  final List<T> strokeMarks = [];
  bool isCommitting = false;
  final List<T> committedMarks = [];
  int committedHash = 0;
  DateTime? _strokeTimestamp;

  /// 点击：取样模式更新 clone source，绘画模式放置单点
  void onTapDown(Offset pos, WidgetRef ref) {
    final isSampling = getIsSampling(ref);
    if (isSampling) {
      paintOffset = null;
      updateCloneSource(ref, screenToSource(pos));
    } else {
      final target = screenToSource(pos);
      final offset = paintOffset;
      if (offset != null) {
        updateCloneSource(
          ref,
          Offset(target.dx + offset.dx, target.dy + offset.dy),
        );
      }
      addSingleMark(ref, target);
    }
  }

  /// 笔画开始：初始化 tracker、计算 paintOffset、创建首 mark
  void onPanStart(Offset pos, WidgetRef ref) {
    final isSampling = getIsSampling(ref);
    if (isSampling) return;
    final ts = DateTime.now();
    _strokeTimestamp = ts;
    final target = screenToSource(pos);
    final Offset source;
    if (paintOffset != null) {
      source = Offset(target.dx + paintOffset!.dx, target.dy + paintOffset!.dy);
    } else {
      final cs = getCloneSource(ref);
      if (cs == null) return;
      source = cs;
      paintOffset = Offset(source.dx - target.dx, source.dy - target.dy);
    }
    final radius = getBrushRadius(ref);
    final hardness = getBrushHardness(ref);
    final tracker = PathBrushTracker(spacing: radius * 0.15);
    tracker.start(target);
    strokeTracker = tracker;

    onStrokeStarted();
    committedMarks.clear();
    isCommitting = false;
    strokeMarks.clear();
    strokeMarks.add(
      createMark(
        source: source,
        target: target,
        radius: radius,
        hardness: hardness,
        createdAt: ts,
      ),
    );
    onNeedsSetState();
  }

  /// 笔画中：沿 tracker 路径添加 marks，触发增量合成
  void onPanUpdate(Offset pos, WidgetRef ref) {
    final tracker = strokeTracker;
    final offset = paintOffset;
    final ts = _strokeTimestamp;
    if (tracker == null || offset == null || ts == null) return;
    final radius = getBrushRadius(ref);
    final hardness = getBrushHardness(ref);
    for (final t in tracker.move(screenToSource(pos))) {
      final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
      strokeMarks.add(
        createMark(
          source: s,
          target: t,
          radius: radius,
          hardness: hardness,
          createdAt: ts,
        ),
      );
    }
    onNeedsSetState();
    onTriggerComposite();
  }

  /// 笔画结束：最终化 tracker、提交管线、持久化、触发全量合成
  ///
  /// [cursorPos] 由调用方（overlay）传入，用于此时更新 clone source
  void onPanEnd(WidgetRef ref, {Offset? cursorPos}) {
    final tracker = strokeTracker;
    final offset = paintOffset;
    final ts = _strokeTimestamp;
    if (tracker != null && offset != null && ts != null) {
      final radius = getBrushRadius(ref);
      final hardness = getBrushHardness(ref);
      for (final t in tracker.end()) {
        strokeMarks.add(
          createMark(
            source: Offset(t.dx + offset.dx, t.dy + offset.dy),
            target: t,
            radius: radius,
            hardness: hardness,
            createdAt: ts,
          ),
        );
      }
    }
    if (offset != null && cursorPos != null) {
      final cursorSrc = screenToSource(cursorPos);
      updateCloneSource(
        ref,
        Offset(cursorSrc.dx + offset.dx, cursorSrc.dy + offset.dy),
      );
    }
    final hadMarks = strokeMarks.isNotEmpty;
    if (hadMarks) {
      commitMarksToPipeline(ref, List<T>.from(strokeMarks));
      committedHash = computeCommittedHash(ref);
      committedMarks
        ..clear()
        ..addAll(strokeMarks);
      isCommitting = true;
      persistMarks(
        ref,
        renderedHashKey,
        committedMarks.map<StampMark>((m) => m).toList(),
        committedHash,
      );
      onTriggerComposite(force: true);
      strokeMarks.clear();
    }
    strokeTracker = null;
    if (hadMarks) onStrokeCommitted?.call();
    onNeedsSetState();
  }

  /// 笔画取消：清空笔画状态，保留 paintOffset
  void onPanCancel() {
    strokeMarks.clear();
    committedMarks.clear();
    isCommitting = false;
    strokeTracker = null;
    onNeedsSetState();
  }
}
