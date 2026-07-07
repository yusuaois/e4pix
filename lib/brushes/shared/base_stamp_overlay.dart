import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/path_brush_tracker.dart';
import '../../utils/shader_pass_util.dart';
import 'spot_data_texture.dart';
import 'stamp_mark.dart';

/// 源-目标型画笔的共享 Overlay State 基类，泛型 [T] 为 mark 类型
///
/// 封装光标、笔画追踪、GPU 增量合成预览、committed preview 生命周期、手势处理
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

  // 笔画追踪
  PathBrushTracker? strokeTracker;
  Offset? paintOffset;
  final List<T> strokeMarks = [];

  // 提交预览
  bool isCommitting = false;
  final List<T> committedMarks = [];
  int committedHash = 0;

  // GPU 增量合成预览
  ui.Image? compositedImage;
  int compositedCount = 0;
  bool compositing = false;
  static const _kCompositeBatchSize = 8;

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

  /// dispose 钩子，在 [dispose] 末尾调用（在 compositedPreview dispose 之后）
  void onCustomDispose() {}

  /// 是否处于交互模式（healing 覆写以支持非交互模式）
  bool get interactive => true;

  //生命周期
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    onInitState();
  }

  @override
  void dispose() {
    _exitDebounce?.cancel();
    _disposeComposited();
    onCustomDispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget as dynamic).sourceImage != sourceImage) {
      _disposeComposited();
      compositedImage = null;
      compositedCount = 0;
    }
  }

  //GPU 合成预览
  // ═══════════════════════════════════════════════════════════

  Offset _screenToSource(Offset screen) => screenToSourceNorm(
    screen: screen,
    imageDisplaySize: imageDisplaySize,
    crop: crop,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );

  void _disposeComposited() {
    compositedImage?.dispose();
    compositedImage = null;
  }

  Future<ui.Image> _runCompositePass({
    required ui.Image base,
    required List<T> marks,
    required ui.FragmentShader shader,
  }) async {
    final count = marks.length.clamp(0, 128);
    final tex = await encodeMarksToTexture(
      count: count,
      maxSpots: 128,
      getMarkFloats: (i) => [
        marks[i].source.dx,
        marks[i].source.dy,
        marks[i].target.dx,
        marks[i].target.dy,
        marks[i].radius,
        marks[i].hardness,
      ],
    );
    try {
      return await runSingleShaderPass(
        shader: shader,
        outputWidth: base.width,
        outputHeight: base.height,
        samplers: [base, tex],
        setUniforms: (s) {
          s.setFloat(0, base.width.toDouble());
          s.setFloat(1, base.height.toDouble());
          s.setFloat(2, count.toDouble());
          s.setFloat(3, tex.width.toDouble());
        },
      );
    } finally {
      tex.dispose();
    }
  }

  /// 异步触发增量合成，带并发守卫
  Future<void> _triggerComposite({bool force = false}) async {
    if (compositing) return;
    final newCount = strokeMarks.length - compositedCount;
    if (!force && newCount < _kCompositeBatchSize) return;
    compositing = true;

    final allNew = strokeMarks.sublist(compositedCount);
    final validMarks = allNew.where((m) {
      return !isMarkSourceFullyOOB(
        sourceX: m.source.dx,
        sourceY: m.source.dy,
        radius: m.radius,
        imageWidth: sourceWidth.toDouble(),
        imageHeight: sourceHeight.toDouble(),
      );
    }).toList();

    if (validMarks.isNotEmpty) {
      final prog = ref.read(brushShaderProgramsProvider).value?[shaderKey];
      final shader = prog?.fragmentShader();
      final base = compositedImage ?? sourceImage;
      if (shader != null && base != null) {
        try {
          final result = await _runCompositePass(
            base: base,
            marks: validMarks,
            shader: shader,
          );
          if (!mounted) {
            result.dispose();
            compositedCount += allNew.length;
            compositing = false;
            return;
          }
          _disposeComposited();
          compositedImage = result;
          compositedCount += allNew.length;
        } catch (e) {
          debugPrint('$logTag composite failed: $e');
          _disposeComposited();
          compositedImage = null;
        }
      }
    } else {
      compositedCount += allNew.length;
    }
    compositing = false;
    if (mounted) setState(() {});
  }

  //Riverpod 监听器（子类在 build() 中调用）
  // ═══════════════════════════════════════════════════════════

  /// 注册 renderedBrushHashesProvider 监听器
  /// 当管线完成渲染且 hash 匹配时，清除 committed preview
  void listenRenderedHashes() {
    ref.listen<Map<String, int>>(renderedBrushHashesProvider, (prev, next) {
      final hash = next[renderedHashKey] ?? 0;
      if (isCommitting && hash == committedHash) {
        committedMarks.clear();
        isCommitting = false;
        _disposeComposited();
        compositedCount = 0;
        if (mounted) setState(() {});
      }
    });
  }

  /// 当外部清空 marks 时的标准清理逻辑
  void handleMarksCleared() {
    committedMarks.clear();
    isCommitting = false;
    _disposeComposited();
    compositedImage = null;
    compositedCount = 0;
    compositing = false;
    if (mounted) setState(() {});
  }

  //手势处理
  // ═══════════════════════════════════════════════════════════

  void _onTapDown(Offset pos, WidgetRef ref) {
    final isSampling = getIsSampling(ref);
    if (isSampling) {
      paintOffset = null;
      updateCloneSource(ref, _screenToSource(pos));
    } else {
      final target = _screenToSource(pos);
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

  void _onPanStart(Offset pos, WidgetRef ref) {
    final isSampling = getIsSampling(ref);
    if (isSampling) return;
    final target = _screenToSource(pos);
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
    cursorPos = pos;

    _disposeComposited();
    compositedImage = null;
    compositedCount = 0;
    committedMarks.clear();
    isCommitting = false;
    strokeMarks.clear();
    strokeMarks.add(
      createMark(
        source: source,
        target: target,
        radius: radius,
        hardness: hardness,
      ),
    );
    setState(() {});
  }

  void _onPanUpdate(Offset pos, WidgetRef ref) {
    final tracker = strokeTracker;
    final offset = paintOffset;
    if (tracker == null || offset == null) return;
    cursorPos = pos;
    final radius = getBrushRadius(ref);
    final hardness = getBrushHardness(ref);
    for (final t in tracker.move(_screenToSource(pos))) {
      final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
      strokeMarks.add(
        createMark(source: s, target: t, radius: radius, hardness: hardness),
      );
    }
    setState(() {});
    _triggerComposite();
  }

  void _onPanEnd(WidgetRef ref) {
    final tracker = strokeTracker;
    final offset = paintOffset;
    if (tracker != null && offset != null) {
      final radius = getBrushRadius(ref);
      final hardness = getBrushHardness(ref);
      for (final t in tracker.end()) {
        strokeMarks.add(
          createMark(
            source: Offset(t.dx + offset.dx, t.dy + offset.dy),
            target: t,
            radius: radius,
            hardness: hardness,
          ),
        );
      }
    }
    if (offset != null && cursorPos != null) {
      final cursorSrc = _screenToSource(cursorPos!);
      updateCloneSource(
        ref,
        Offset(cursorSrc.dx + offset.dx, cursorSrc.dy + offset.dy),
      );
    }
    if (strokeMarks.isNotEmpty) {
      commitMarksToPipeline(ref, List<T>.from(strokeMarks));
      committedHash = computeCommittedHash(ref);
      committedMarks
        ..clear()
        ..addAll(strokeMarks);
      isCommitting = true;
      _triggerComposite(force: true);
      strokeMarks.clear();
      compositedCount = 0;
    }
    strokeTracker = null;
    setState(() {});
  }

  void _onPanCancel() {
    strokeMarks.clear();
    compositedCount = 0;
    committedMarks.clear();
    isCommitting = false;
    compositing = false;
    strokeTracker = null;
    _disposeComposited();
    compositedImage = null;
    setState(() {});
  }

  //build() 辅助
  // ═══════════════════════════════════════════════════════════

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
      child: GestureDetector(
        onTapDown: (d) => _onTapDown(d.localPosition, ref),
        onPanStart: (d) => _onPanStart(d.localPosition, ref),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, ref),
        onPanEnd: (_) => _onPanEnd(ref),
        onPanCancel: _onPanCancel,
        behavior: HitTestBehavior.translucent,
        child: painter,
      ),
    );
  }

  /// 获取光标归一化源图坐标（用于 Painter 的 cursorSrc 参数）
  Offset? get cursorSrc =>
      (cursorVisible && cursorPos != null) ? _screenToSource(cursorPos!) : null;
}
