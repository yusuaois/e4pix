import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../render/hi_res_geometry.dart';
import '../../state/providers.dart';
import '../../utils/debouncer.dart';

/// 高清瓦片覆盖层：zoom 超过阈值后，从全尺寸裁剪后输出图按视口切瓦片，
/// 覆盖在低清底图之上、画笔 overlay 之下。
///
/// 瓦片固定在上次提取的 displaySize 坐标位置（随 InteractiveViewer 变换），
/// 平移时移出可见区域被裁剪、底图兜底；平移停止 100ms 后才后台提取新瓦片，
/// 避免平移过程中频繁 GPU 提取导致掉帧。
class HiResTileLayer extends ConsumerStatefulWidget {
  final Size displaySize;
  final Size viewportSize;
  const HiResTileLayer({
    super.key,
    required this.displaySize,
    required this.viewportSize,
  });

  @override
  ConsumerState<HiResTileLayer> createState() => _HiResTileLayerState();
}

class _HiResTileLayerState extends ConsumerState<HiResTileLayer> {
  ui.Image? _tile;
  Rect? _tileDst; // 瓦片在 displaySize 坐标的位置（提取时的可见区域）
  int _gen = 0;
  final _debouncer = Debouncer();

  @override
  Widget build(BuildContext context) {
    final full = ref.watch(hiResCroppedImageProvider.select((s) => s.image));
    final zoom = ref.watch(zoomScaleProvider);
    ref.watch(viewportTransformProvider); // 缩放/平移触发重建

    if (full == null || zoom < kHiResZoomThreshold) {
      return const SizedBox.shrink();
    }

    final rects = computeTileRects(
      viewportTransform: ref.read(viewportTransformProvider),
      viewportSize: widget.viewportSize,
      displaySize: widget.displaySize,
      fullOutSize: Size(full.width.toDouble(), full.height.toDouble()),
    );
    if (rects == null) return const SizedBox.shrink();

    // 平移停止 100ms 后才提取（后台静默，不阻塞平移帧）
    _debouncer.run(const Duration(milliseconds: 100), () {
      _extract(
        full,
        rects.src,
        rects.dst,
        zoom,
        MediaQuery.devicePixelRatioOf(context),
      );
    });

    final tile = _tile;
    final tileDst = _tileDst;
    if (tile == null || tileDst == null) return const SizedBox.shrink();

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: tileDst,
            child: RawImage(image: tile, fit: BoxFit.fill),
          ),
        ],
      ),
    );
  }

  Future<void> _extract(
    ui.Image full,
    Rect src,
    Rect dst,
    double zoom,
    double dpr,
  ) async {
    final gen = ++_gen;
    final res = tileResolution(
      src: src,
      dst: dst,
      zoom: zoom,
      devicePixelRatio: dpr,
    );
    final tile = await extractTile(full, src, res.w, res.h);
    if (gen != _gen || !mounted) {
      tile.dispose();
      return;
    }
    final old = _tile;
    setState(() {
      _tile = tile;
      _tileDst = dst;
    });
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          old.dispose();
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _tile?.dispose();
    super.dispose();
  }
}
