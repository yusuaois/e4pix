import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import 'clone_stamp_model.dart';
import 'clone_stamp_cache.dart';
import '../../state/providers.dart';
import '../../utils/brush_coord_utils.dart';
import '../../utils/brush_preview_utils.dart';
import '../../utils/path_brush_tracker.dart';

/// 污点修复交互覆盖层
///
/// PS 风格交互：
/// - 按住取样键（默认 Alt）：白色取样圈 + 十字，点击设置源点
/// - 松开采样键：红色目标圈，点击/拖拽涂抹
/// - 手机用户可通过 Section 中的 "取样" 按钮切换取样模式
///
/// **笔画中即时反馈**：拖拽时，克隆像素直接在 overlay 的 Canvas 上绘制
/// （[_SpotPainter] 遍历 [_strokeSpots] 逐点绘制），无需等待管线重渲染
/// 松手后一次性提交给管线做最终融合（含硬度渐变），同时清空本地预览
class SpotRemoveOverlay extends ConsumerStatefulWidget {
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image? sourceImage;

  const SpotRemoveOverlay({
    super.key,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    this.sourceImage,
  });

  @override
  ConsumerState<SpotRemoveOverlay> createState() => _SpotRemoveOverlayState();
}

class _SpotRemoveOverlayState extends ConsumerState<SpotRemoveOverlay> {
  Offset? _cursorPos;
  bool _isHovering = false;
  Timer? _exitDebounce;
  PathBrushTracker? _tracker;
  Offset? _paintOffset; // 拖拽时源点相对目标点的固定偏移（PS 仿制图章行为）

  // ── 笔画内本地积攒（不触发管线）──
  final List<SpotMark> _strokeSpots = [];

  // ── 已提交但管线尚未渲染完成的预览（避免松手后画面消失）──
  bool _isCommitting = false;
  final List<SpotMark> _committedPreview = [];
  int _committedSpotsHash = 0; // 描边提交时的 spots hash，用于匹配渲染结果

  @override
  void dispose() {
    _exitDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotRemoveStateProvider);
    final isSampling = state.samplingButtonOn;

    // 只有当"包含本次描边的渲染"完成时才清除 committed preview
    // 使用 spots hash 匹配避免被滑块拖动等无关渲染的完成误触发
    ref.listen<int>(renderedSpotsHashProvider, (prev, next) {
      if (_isCommitting && next == _committedSpotsHash) {
        _committedPreview.clear();
        _isCommitting = false;
        if (mounted) setState(() {});
      }
    });

    return MouseRegion(
      onEnter: (_) {
        _exitDebounce?.cancel();
        if (!_isHovering) setState(() => _isHovering = true);
      },
      onHover: (e) {
        _exitDebounce?.cancel();
        setState(() {
          _isHovering = true;
          _cursorPos = e.localPosition;
        });
      },
      onExit: (_) {
        // 延迟 50ms，过滤 Riverpod rebuild 引发的假 onExit
        _exitDebounce = Timer(const Duration(milliseconds: 50), () {
          if (mounted) setState(() => _isHovering = false);
        });
      },
      child: GestureDetector(
        onTapDown: (d) => _onTapDown(d.localPosition, state, isSampling),
        onPanStart: (d) => _onPanStart(d.localPosition, state, isSampling),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, state),
        onPanEnd: (_) => _onPanEnd(),
        onPanCancel: _onPanCancel,
        behavior: HitTestBehavior.translucent,
        child: CustomPaint(
          size: widget.imageDisplaySize,
          painter: _SpotPainter(
            cloneSource: state.cloneSource,
            brushRadius: state.brushRadius,
            brushHardness: state.brushHardness,
            imageDisplaySize: widget.imageDisplaySize,
            crop: widget.crop,
            sourceWidth: widget.sourceWidth,
            sourceHeight: widget.sourceHeight,
            cursorPos: _isHovering ? _cursorPos : null,
            cursorSrc: (_isHovering && _cursorPos != null)
                ? _screenToSource(_cursorPos!)
                : null,
            isSampling: isSampling,
            paintOffset: _paintOffset,
            isPainting: _tracker != null,
            sourceImage: widget.sourceImage,
            strokeSpots: _strokeSpots,
            committedSpots: _committedPreview,
          ),
        ),
      ),
    );
  }

  Offset _screenToSource(Offset screen) => screenToSourceNorm(
    screen: screen,
    imageDisplaySize: widget.imageDisplaySize,
    crop: widget.crop,
    sourceWidth: widget.sourceWidth,
    sourceHeight: widget.sourceHeight,
  );

  void _onTapDown(Offset pos, SpotRemoveState state, bool isSampling) {
    if (isSampling) {
      // 设置新源点时清除旧偏移，下次下笔重新计算
      _paintOffset = null;
      ref
          .read(spotRemoveStateProvider.notifier)
          .setCloneSource(_screenToSource(pos));
    } else {
      final target = _screenToSource(pos);
      // 保持已建立的偏移关系：先更新 cloneSource 再创建 spot
      final offset = _paintOffset;
      if (offset != null) {
        ref
            .read(spotRemoveStateProvider.notifier)
            .setCloneSource(
              Offset(target.dx + offset.dx, target.dy + offset.dy),
            );
      }
      ref.read(spotRemoveStateProvider.notifier).addSpot(target);
    }
  }

  void _onPanStart(Offset pos, SpotRemoveState state, bool isSampling) {
    if (isSampling) return;
    final target = _screenToSource(pos);
    final Offset source;
    if (_paintOffset != null) {
      // 已有偏移：从 target + 偏移反算 source，保持偏移一致性
      source = Offset(
        target.dx + _paintOffset!.dx,
        target.dy + _paintOffset!.dy,
      );
    } else {
      // 首次下笔：从 cloneSource 建立偏移
      final cs = state.cloneSource;
      if (cs == null) return;
      source = cs;
      _paintOffset = Offset(source.dx - target.dx, source.dy - target.dy);
    }
    final tracker = PathBrushTracker(spacing: state.brushRadius * 0.5);
    tracker.start(target);
    _tracker = tracker;
    _cursorPos = pos; // 下笔时立刻更新光标位置

    // 开始新笔画：清空本地积攒
    _strokeSpots.clear();

    // 起始点加入本地列表
    _strokeSpots.add(
      SpotMark(
        source: source,
        target: target,
        radius: state.brushRadius,
        hardness: state.brushHardness,
      ),
    );
    setState(() {});
  }

  void _onPanUpdate(Offset pos, SpotRemoveState state) {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker == null || offset == null) return;
    _cursorPos = pos;
    for (final t in tracker.move(_screenToSource(pos))) {
      final s = Offset(t.dx + offset.dx, t.dy + offset.dy);
      _strokeSpots.add(
        SpotMark(
          source: s,
          target: t,
          radius: state.brushRadius,
          hardness: state.brushHardness,
        ),
      );
    }
    // 触发重绘：_strokeSpots 已新增元素，通知 painter 重绘
    setState(() {});
  }

  void _onPanEnd() {
    final tracker = _tracker;
    final offset = _paintOffset;
    if (tracker != null && offset != null) {
      final s = ref.read(spotRemoveStateProvider);
      for (final t in tracker.end()) {
        _strokeSpots.add(
          SpotMark(
            source: Offset(t.dx + offset.dx, t.dy + offset.dy),
            target: t,
            radius: s.brushRadius,
            hardness: s.brushHardness,
          ),
        );
      }
    }
    // 更新 cloneSource 为当前光标位置 + 偏移（PS 行为：松手后源点更新）
    if (offset != null && _cursorPos != null) {
      final cursorSrc = _screenToSource(_cursorPos!);
      ref
          .read(spotRemoveStateProvider.notifier)
          .setCloneSource(
            Offset(cursorSrc.dx + offset.dx, cursorSrc.dy + offset.dy),
          );
    }
    // 笔画结束：一次性提交所有 spots 给管线，保留本地预览直到管线渲染完成
    if (_strokeSpots.isNotEmpty) {
      ref
          .read(spotRemoveStateProvider.notifier)
          .addSpotsBatch(List<SpotMark>.from(_strokeSpots));
      // NOTE: We compute the spots hash at commit time rather than reading
      // renderedSpotsHashProvider because the pipeline hasn't rendered yet.
      // This value is the "expected" hash that we match against when the
      // pipeline completes and updates renderedSpotsHashProvider.
      _committedSpotsHash = SpotRemovalCache.computeSpotsKey(
        ref.read(currentParamsNotifierProvider).spots,
      );
      // 将笔画移入已提交预览——管线渲染完成前继续绘制这些圆
      _committedPreview.addAll(_strokeSpots);
      _isCommitting = true;
      _strokeSpots.clear();
    }
    _tracker = null;
    // 保留 _paintOffset，松手后源点继续跟随光标移动
    setState(() {});
  }

  /// 手势取消（如系统返回手势抢占）：丢弃本地积攒，不提交
  void _onPanCancel() {
    _strokeSpots.clear();
    _committedPreview.clear();
    _isCommitting = false;
    _tracker = null;
    setState(() {});
  }
}

// ═══════════════════════════════════════════════════════════
// 绘制
// ═══════════════════════════════════════════════════════════

class _SpotPainter extends CustomPainter {
  final Offset? cloneSource;
  final double brushRadius;
  final double brushHardness;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final Offset? cursorPos;
  final Offset? cursorSrc;
  final bool isSampling;
  final Offset? paintOffset;
  final bool isPainting;
  final ui.Image? sourceImage;
  final List<SpotMark> strokeSpots;
  final List<SpotMark> committedSpots;

  // 共用 Paint，启用双线性过滤避免锯齿
  static final _imagePaint = Paint()..filterQuality = FilterQuality.low;

  _SpotPainter({
    required this.cloneSource,
    required this.brushRadius,
    required this.brushHardness,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cursorPos,
    required this.cursorSrc,
    required this.isSampling,
    this.paintOffset,
    this.isPainting = false,
    this.sourceImage,
    this.strokeSpots = const [],
    this.committedSpots = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── 先绘制笔画中已累积的克隆像素（硬边即时预览）──
    // 包括正在绘制的笔画 + 已提交但管线尚未渲染完成的笔画
    final img = sourceImage;
    final allPreview = <SpotMark>[...strokeSpots, ...committedSpots];
    if (allPreview.isNotEmpty && img != null) {
      for (final spot in allPreview) {
        _drawStrokeSpot(canvas, img, spot);
      }
    }

    if (cursorPos == null || cursorSrc == null) return;

    final r = sourceRadiusToScreen(
      r: brushRadius,
      srcCenter: cursorSrc!,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );

    if (isSampling) {
      // 取样模式：白圈 + 十字
      _drawSamplingCursor(canvas, cursorPos!, r);
    } else if (!isPainting && cloneSource != null && sourceImage != null) {
      // 悬停（未按下）：白圈内显示源点区域预览
      final previewSrc = paintOffset != null
          ? Offset(
              cursorSrc!.dx + paintOffset!.dx,
              cursorSrc!.dy + paintOffset!.dy,
            )
          : cloneSource!;
      _drawPreviewCursor(canvas, cursorPos!, r, previewSrc);
    } else {
      // 按下绘制 / 无源点：白圈
      _drawTargetCursor(canvas, cursorPos!, r);
    }

    // 非取样模式下，在源点位置绘制十字标记
    if (!isSampling && cloneSource != null) {
      final Offset srcScreen;
      if (paintOffset != null) {
        srcScreen = sourceToScreenNorm(
          src: Offset(
            cursorSrc!.dx + paintOffset!.dx,
            cursorSrc!.dy + paintOffset!.dy,
          ),
          imageDisplaySize: imageDisplaySize,
          crop: crop,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
      } else {
        srcScreen = sourceToScreenNorm(
          src: cloneSource!,
          imageDisplaySize: imageDisplaySize,
          crop: crop,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
        );
      }
      _drawSourceCrosshair(canvas, srcScreen);
    }
  }

  /// 绘制单笔克隆圆（硬边即时预览；硬度融合由管线 shader 处理）
  ///
  /// OOB 处理：采样区域按与图像边界的交集做比例映射，
  /// 只绘制有效像素，界外部分透明（不拉伸边缘像素）
  void _drawStrokeSpot(Canvas canvas, ui.Image img, SpotMark spot) {
    final sxRaw = spot.source.dx * img.width;
    final syRaw = spot.source.dy * img.height;
    final pr = (spot.radius * img.width).clamp(1.0, img.width / 2.0);

    // 目标圆在屏幕上的位置（完整的圆）
    final screenCenter = sourceToScreenNorm(
      src: spot.target,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    final screenR = sourceRadiusToScreen(
      r: spot.radius,
      srcCenter: spot.target,
      imageDisplaySize: imageDisplaySize,
      crop: crop,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );

    final rects = computeOOBRects(
      sxRaw: sxRaw,
      syRaw: syRaw,
      pr: pr,
      imageW: img.width.toDouble(),
      imageH: img.height.toDouble(),
      screenCenterX: screenCenter.dx,
      screenCenterY: screenCenter.dy,
      screenR: screenR,
    );
    if (rects == null) return;

    // clip 到圆形后绘制（只绘制 dstRect 与圆的交集部分）
    canvas.save();
    canvas.clipPath(Path()..addOval(rects.fullDstRect));
    canvas.drawImageRect(img, rects.srcRect, rects.dstRect, _imagePaint);
    canvas.restore();
  }

  /// 取样光标：白圈 + 十字（PS 风格）
  void _drawSamplingCursor(Canvas canvas, Offset pos, double radius) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(pos, radius, p);
    final len = radius * 0.6;
    final gap = radius * 0.15;
    canvas.drawLine(
      Offset(pos.dx - len, pos.dy),
      Offset(pos.dx - gap, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx + gap, pos.dy),
      Offset(pos.dx + len, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy - len),
      Offset(pos.dx, pos.dy - gap),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + gap),
      Offset(pos.dx, pos.dy + len),
      p,
    );
  }

  /// 目标光标：白圈
  void _drawTargetCursor(Canvas canvas, Offset pos, double radius) {
    canvas.drawCircle(
      pos,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  /// 源点十字标记（非取样模式下显示）
  void _drawSourceCrosshair(Canvas canvas, Offset pos) {
    const size = 8.0;
    const gap = 2.0;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(pos.dx - size, pos.dy),
      Offset(pos.dx - gap, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx + gap, pos.dy),
      Offset(pos.dx + size, pos.dy),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy - size),
      Offset(pos.dx, pos.dy - gap),
      p,
    );
    canvas.drawLine(
      Offset(pos.dx, pos.dy + gap),
      Offset(pos.dx, pos.dy + size),
      p,
    );
  }

  /// 悬停预览：白圈内显示源点区域的圆形预览，边缘根据硬度显示柔边渐变
  ///
  /// OOB 处理：与 _drawStrokeSpot 一致的比例映射——
  /// 只绘制有效像素区域，界外部分透明
  void _drawPreviewCursor(
    Canvas canvas,
    Offset screenPos,
    double radius,
    Offset srcNorm,
  ) {
    final img = sourceImage;
    if (img == null) return;

    final srxRaw = srcNorm.dx * img.width;
    final sryRaw = srcNorm.dy * img.height;
    final pr = (brushRadius * img.width).clamp(1.0, img.width / 2.0);

    final rects = computeOOBRects(
      sxRaw: srxRaw,
      syRaw: sryRaw,
      pr: pr,
      imageW: img.width.toDouble(),
      imageH: img.height.toDouble(),
      screenCenterX: screenPos.dx,
      screenCenterY: screenPos.dy,
      screenR: radius,
    );
    if (rects == null) {
      // 采样区域完全在界外：只显示轮廓圆，不显示内容预览
      _drawTargetCursor(canvas, screenPos, radius);
      return;
    }

    if (brushHardness >= 0.99) {
      canvas.save();
      canvas.clipPath(Path()..addOval(rects.fullDstRect));
      canvas.drawImageRect(img, rects.srcRect, rects.dstRect, _imagePaint);
      canvas.restore();
    } else {
      final t0 = brushHardness.clamp(0.0, 1.0);
      final span = 1.0 - t0;
      double ss(double t) => (3 * t * t - 2 * t * t * t).clamp(0.0, 1.0);
      final gradient = ui.Gradient.radial(
        screenPos,
        radius,
        [
          Colors.white,
          if (span > 0.01) ...{
            Colors.white,
            Colors.white.withValues(alpha: 1.0 - ss(0.25)),
            Colors.white.withValues(alpha: 1.0 - ss(0.5)),
            Colors.white.withValues(alpha: 1.0 - ss(0.75)),
          },
          Colors.transparent,
        ],
        [
          0.0,
          if (span > 0.01) ...{
            t0,
            t0 + span * 0.25,
            t0 + span * 0.5,
            t0 + span * 0.75,
          },
          1.0,
        ],
      );

      canvas.saveLayer(rects.fullDstRect, Paint());
      canvas.drawImageRect(img, rects.srcRect, rects.dstRect, _imagePaint);
      canvas.drawRect(
        rects.fullDstRect,
        Paint()
          ..shader = gradient
          ..blendMode = ui.BlendMode.dstIn,
      );
      canvas.restore();
    }

    // 轮廓圆（始终显示，不受内容 OOB 影响）
    canvas.drawCircle(
      screenPos,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.cloneSource != cloneSource ||
      old.brushRadius != brushRadius ||
      old.brushHardness != brushHardness ||
      old.cursorPos != cursorPos ||
      old.cursorSrc != cursorSrc ||
      old.isSampling != isSampling ||
      old.isPainting != isPainting ||
      old.paintOffset != paintOffset ||
      old.sourceImage != sourceImage ||
      !listEquals(old.strokeSpots, strokeSpots) ||
      !listEquals(old.committedSpots, committedSpots) ||
      old.imageDisplaySize != imageDisplaySize ||
      old.crop != crop ||
      old.sourceWidth != sourceWidth ||
      old.sourceHeight != sourceHeight;
}
