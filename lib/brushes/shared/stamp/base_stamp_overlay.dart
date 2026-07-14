import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/crop_params.dart';
import '../../../state/providers.dart';
import '../single_pointer_gesture_detector.dart';
import 'stamp_compositor.dart';
import 'stamp_gesture_handler.dart';
import 'stamp_mark.dart';

/// 源-目标型画笔的共享 Overlay State 基类，泛型 [T] 为 mark 类型
///
/// 职责：光标管理、生命周期编排、Riverpod 监听器、手势→合成桥接
/// 笔画状态委托给 [StampGestureHandler]，GPU 合成委托给 [StampCompositor]
///
/// 子类提供 5 个 widget getter + 10 个 brush 配置抽象方法
/// 可选覆写 [onInitState]/[onCustomDispose]/[interactive]（healing 专用）
abstract class BaseStampOverlayState<
  T extends StampMark,
  W extends ConsumerStatefulWidget
>
    extends ConsumerState<W> {
  // 光标/悬停
  Offset? cursorPos;
  bool cursorVisible = false;
  Timer? _exitDebounce;

  // 委托对象
  late final StampGestureHandler<T> _gestureHandler;
  late final StampCompositor<T> _compositor;

  /// 子类可访问笔画状态（build painter、didUpdateWidget、onInitState）
  @protected
  StampGestureHandler<T> get gestureHandler => _gestureHandler;

  /// 子类可访问合成预览（build painter、didUpdateWidget）
  @protected
  StampCompositor<T> get compositor => _compositor;

  // Widget 参数——子类委托给 widget.*

  Size get imageDisplaySize;
  CropParams get crop;
  int get sourceWidth;
  int get sourceHeight;
  ui.Image? get sourceImage;

  // Brush 配置——子类实现

  /// shader program 在 [brushShaderProgramsProvider] 中的 key
  String get shaderKey;

  /// 日志标签，用于 debugPrint
  String get logTag;

  /// 在 [renderedBrushHashesProvider] 中的 key
  String get renderedHashKey;

  /// 创建 mark 实例的工厂方法
  T createMark({
    required Offset source,
    required Offset target,
    required double radius,
    required double hardness,
    required DateTime createdAt,
  });

  /// 批量提交 marks 到管线
  void commitMarksToPipeline(WidgetRef ref, List<T> marks);

  /// 提交后计算管线中所有 marks 的哈希（从 AdjustmentParams 读取）
  int computeCommittedHash(WidgetRef ref);

  /// 单次点击时添加单个 mark（clone: addSpot / healing: addMark）
  void addSingleMark(WidgetRef ref, Offset target);

  /// 更新克隆源位置
  void updateCloneSource(WidgetRef ref, Offset source);

  /// 读取 brush radius（归一化 0..1）
  double getBrushRadius(WidgetRef ref);

  /// 读取 brush hardness
  double getBrushHardness(WidgetRef ref);

  /// 读取 clone source（可能为 null）
  Offset? getCloneSource(WidgetRef ref);

  /// 读取是否处于取样模式
  bool getIsSampling(WidgetRef ref);

  // 可选覆写

  /// initState 钩子，在 [initState] 末尾调用
  void onInitState() {}

  /// dispose 钩子，在 [dispose] 末尾调用（在 compositor dispose 之后）
  void onCustomDispose() {}

  /// 是否处于交互模式（healing 覆写以支持非交互模式）
  bool get interactive => true;

  // 生命周期

  @override
  void initState() {
    super.initState();

    _compositor = StampCompositor<T>(
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      getSourceImage: () => sourceImage,
      logTag: logTag,
      shaderKey: shaderKey,
      isMounted: () => mounted,
      onNeedsRebuild: () {
        if (mounted) setState(() {});
      },
    );

    _gestureHandler = StampGestureHandler<T>(
      createMark: createMark,
      getBrushRadius: getBrushRadius,
      getBrushHardness: getBrushHardness,
      getCloneSource: getCloneSource,
      getIsSampling: getIsSampling,
      updateCloneSource: updateCloneSource,
      addSingleMark: addSingleMark,
      commitMarksToPipeline: commitMarksToPipeline,
      computeCommittedHash: computeCommittedHash,
      renderedHashKey: renderedHashKey,
      persistMarks: (ref, key, marks, hash) {
        ref.read(persistedStampProvider.notifier).persist(key, marks, hash);
      },
      screenToSource: _compositor.screenToSource,
      onNeedsSetState: () {
        if (mounted) setState(() {});
      },
      onStrokeStarted: () {
        _compositor.reset();
      },
      onTriggerComposite: ({bool force = false}) {
        _compositor.triggerComposite(
          ref,
          strokeMarks: _gestureHandler.strokeMarks,
          force: force,
        );
      },
      onStrokeCommitted: () {
        // 通知 History 面板捕获新的笔画条目
        ref.read(historyPanelProvider.notifier).captureStroke(logTag);
      },
    );

    onInitState();
  }

  @override
  void dispose() {
    _exitDebounce?.cancel();
    _compositor.disposeComposited();
    onCustomDispose();
    super.dispose();
  }

  // Riverpod 监听器（子类在 build() 中调用）

  /// 注册 renderedBrushHashesProvider 监听器
  /// 当管线完成渲染且 hash 匹配时，清除 committed preview
  void listenRenderedHashes() {
    ref.listen<Map<String, int>>(renderedBrushHashesProvider, (prev, next) {
      final hash = next[renderedHashKey] ?? 0;
      if (_gestureHandler.isCommitting &&
          hash == _gestureHandler.committedHash) {
        _gestureHandler.committedMarks.clear();
        _gestureHandler.isCommitting = false;
        _compositor.disposeComposited();
        _compositor.compositedCount = 0;
        ref.read(persistedStampProvider.notifier).clear();
        if (mounted) setState(() {});
      }
    });
  }

  /// 当外部清空 marks 时的标准清理逻辑
  void handleMarksCleared() {
    _gestureHandler.committedMarks.clear();
    _gestureHandler.isCommitting = false;
    _compositor.disposeComposited();
    _compositor.compositedImage = null;
    _compositor.compositedCount = 0;
    _compositor.compositing = false;
    ref.read(persistedStampProvider.notifier).clear();
    if (mounted) setState(() {});
  }

  // 手势处理——委托给 StampGestureHandler

  void _onTapDown(Offset pos, WidgetRef ref) {
    cursorVisible = true;
    cursorPos = pos;
    _gestureHandler.onTapDown(pos, ref);
  }

  void _onTapUp(_, WidgetRef ref) {
    _gestureHandler.onTapUp(ref);
  }

  void _onPanStart(Offset pos, WidgetRef ref) {
    cursorVisible = true;
    cursorPos = pos;
    _gestureHandler.onPanStart(pos, ref);
  }

  void _onPanUpdate(Offset pos, WidgetRef ref) {
    cursorPos = pos;
    _gestureHandler.onPanUpdate(pos, ref);
  }

  void _onPanEnd(WidgetRef ref) {
    _gestureHandler.onPanEnd(ref, cursorPos: cursorPos);
    cursorVisible = false;
  }

  void _onPanCancel() {
    _gestureHandler.onPanCancel();
    _compositor.reset();
  }

  // build() 辅助

  /// 构建标准的 MouseRegion + GestureDetector 包装
  ///
  /// [painter] 是 CustomPaint widget，[isSampling] 控制手势行为
  /// [interactiveOverride] 为 false 时返回 IgnorePointer（非交互模式）
  Widget buildInteractionWrapper({
    required Widget painter,
    required WidgetRef ref,
    bool interactiveOverride = true,
  }) {
    if (!interactiveOverride) return IgnorePointer(child: painter);

    return MouseRegion(
      onEnter: (_) {
        _exitDebounce?.cancel();
        if (!cursorVisible) setState(() => cursorVisible = true);
      },
      onHover: (e) {
        _exitDebounce?.cancel();
        setState(() {
          cursorVisible = true;
          cursorPos = e.localPosition;
        });
      },
      onExit: (_) {
        _exitDebounce = Timer(const Duration(milliseconds: 50), () {
          if (mounted) setState(() => cursorVisible = false);
        });
      },
      child: SinglePointerGestureDetector(
        onTapDown: (d) => _onTapDown(d.localPosition, ref),
        onTapUp: (d) => _onTapUp(d, ref),
        onPanStart: (d) => _onPanStart(d.localPosition, ref),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, ref),
        onPanEnd: (_) => _onPanEnd(ref),
        onPanCancel: _onPanCancel,
        child: painter,
      ),
    );
  }

  /// 获取光标归一化源图坐标（用于 Painter 的 cursorSrc 参数）
  Offset? get cursorSrc =>
      cursorPos != null ? _compositor.screenToSource(cursorPos!) : null;
}
