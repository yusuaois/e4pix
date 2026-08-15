import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../render/crop_transform.dart';
import '../../render/hi_res/hi_res_geometry.dart';
import '../../render/hi_res/hi_res_pyramid.dart';
import '../../render/hi_res/hi_res_tile_grid.dart';
import '../../state/providers.dart';
import '../../utils/debouncer.dart';

/// 高清瓦片覆盖层：按固定网格切瓦片，单一 CustomPainter 一次画完可见瓦片
class HiResTileGridLayer extends ConsumerStatefulWidget {
  final Size displaySize;
  final Size viewportSize;
  const HiResTileGridLayer({
    super.key,
    required this.displaySize,
    required this.viewportSize,
  });

  @override
  ConsumerState<HiResTileGridLayer> createState() => _HiResTileGridLayerState();
}

class _HiResTileGridLayerState extends ConsumerState<HiResTileGridLayer> {
  static const int _kMaxTiles = 64;

  /// 瓦片缓存（LinkedHashMap 提供插入序，LRU 用「remove+reinsert」把访问过的移到最后）
  final LinkedHashMap<HiResTileId, ui.Image> _tiles = LinkedHashMap();

  /// 当前可见瓦片布局（仅在上次提取时更新，平移期间保持不变、靠 transform 移动）
  List<({HiResTileId id, Rect src, Rect dst})> _layout = const [];

  ui.Image? _cacheSrc; // 缓存对应的全尺寸源图
  int _cacheParamsHash = 0; // 缓存对应的参数 hash
  int _gen = 0;
  int _paintGen = 0;
  final _debouncer = Debouncer();

  @override
  Widget build(BuildContext context) {
    final renderState = ref.watch(hiResRenderProvider);
    final levels = renderState.levels;
    final src = ref.watch(hiResSourceProvider);
    final zoom = ref.watch(zoomScaleProvider);
    ref.watch(viewportTransformProvider); // 缩放/平移触发重建

    if (src == null || levels.isEmpty || zoom < kHiResZoomThreshold) {
      return const SizedBox.shrink();
    }

    final params = ref.read(debouncedParamsProvider);

    // 图片切换 / 参数变化：清空旧图瓦片缓存
    if (!identical(src, _cacheSrc) || params.hashCode != _cacheParamsHash) {
      _cacheSrc = src;
      _cacheParamsHash = params.hashCode;
      _clearCache();
    }

    final fullOutSize = cropOutputSize(params.crop, src.width, src.height);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    final desiredLevel = selectPyramidLevel(
      zoom: zoom,
      devicePixelRatio: dpr,
      displaySize: widget.displaySize,
      fullOutSize: fullOutSize,
    );
    // 首选目标层级；未渲染完则回退到最高分辨率可用层级
    final level = levels.containsKey(desiredLevel)
        ? desiredLevel
        : levels.keys.reduce(math.min);
    final levelImage = levels[level]!;

    final rects = computeTileRects(
      viewportTransform: ref.read(viewportTransformProvider),
      viewportSize: widget.viewportSize,
      displaySize: widget.displaySize,
      fullOutSize: fullOutSize,
    );
    if (rects == null) return const SizedBox.shrink();

    // 可见区从 L0（裁剪后全尺寸）坐标映射到当前层级坐标（用实际图尺寸比，避免取整错位）
    final sx = levelImage.width / fullOutSize.width;
    final sy = levelImage.height / fullOutSize.height;
    final visibleSrc = Rect.fromLTRB(
      rects.src.left * sx,
      rects.src.top * sy,
      rects.src.right * sx,
      rects.src.bottom * sy,
    );
    final levelSize = Size(
      levelImage.width.toDouble(),
      levelImage.height.toDouble(),
    );

    // 平移停止 100ms 后才提取（后台静默，不阻塞平移帧）
    _debouncer.run(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _extract(levelImage, visibleSrc, level, levelSize);
    });

    return SizedBox.expand(
      child: CustomPaint(
        painter: _HiResTileGridPainter(
          tiles: _tiles,
          layout: _layout,
          generation: _paintGen,
        ),
      ),
    );
  }

  /// 计算当前可见瓦片布局，淘汰离屏瓦片，提取缺失瓦片。
  void _extract(ui.Image source, Rect visibleSrc, int level, Size levelSize) {
    final gen = ++_gen;
    final layout = computeGridTiles(
      visibleSrc: visibleSrc,
      fullOutSize: levelSize,
      displaySize: widget.displaySize,
      tileEdge: kHiResGridTileEdge,
      level: level,
    );
    final neededIds = layout.map((t) => t.id).toSet();

    // 触摸已缓存可见瓦片（LRU move-to-end）
    for (final id in neededIds) {
      final img = _tiles.remove(id);
      if (img != null) _tiles[id] = img;
    }

    // 超容时优先淘汰离屏瓦片（LRU 前部）
    if (_tiles.length > _kMaxTiles) {
      for (final id in _tiles.keys.toList()) {
        if (_tiles.length <= _kMaxTiles) break;
        if (neededIds.contains(id)) continue;
        final img = _tiles.remove(id);
        if (img != null) _disposeLater(img);
      }
    }

    // 提取缺失瓦片（1:1 全分辨率）
    for (final t in layout) {
      if (_tiles.containsKey(t.id)) continue;
      final w = t.src.width.round();
      final h = t.src.height.round();
      _extractOne(source, t.id, t.src, w, h, gen);
    }

    setState(() {
      _layout = layout;
      _paintGen++;
    });
  }

  Future<void> _extractOne(
    ui.Image source,
    HiResTileId id,
    Rect src,
    int w,
    int h,
    int gen,
  ) async {
    final tile = await extractTile(source, src, w, h);
    if (gen != _gen || !mounted) {
      tile.dispose();
      return;
    }
    final old = _tiles[id];
    setState(() {
      _tiles[id] = tile;
      _paintGen++;
    });
    if (old != null) _disposeLater(old);
  }

  void _clearCache() {
    for (final img in _tiles.values) {
      _disposeLater(img);
    }
    _tiles.clear();
    _layout = const [];
    _paintGen++;
  }

  void _disposeLater(ui.Image img) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      try {
        img.dispose();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    for (final img in _tiles.values) {
      img.dispose();
    }
    _tiles.clear();
    super.dispose();
  }
}

/// 单一画布：一次 paint 遍历可见瓦片，`drawImageRect` 画到 displaySize 坐标。
class _HiResTileGridPainter extends CustomPainter {
  final Map<HiResTileId, ui.Image> tiles;
  final List<({HiResTileId id, Rect src, Rect dst})> layout;
  final int generation;

  const _HiResTileGridPainter({
    required this.tiles,
    required this.layout,
    required this.generation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final t in layout) {
      final img = tiles[t.id];
      if (img == null) continue; // 未提取到的瓦片跳过，底图兜底
      canvas.drawImageRect(
        img,
        Offset.zero & Size(img.width.toDouble(), img.height.toDouble()),
        t.dst,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HiResTileGridPainter oldDelegate) =>
      oldDelegate.generation != generation;
}
