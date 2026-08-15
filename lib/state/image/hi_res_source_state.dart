import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/raw_formats.dart';
import '../../native/raw_bridge.dart';
import '../../render/raw_to_ui_image.dart';
import '../providers.dart';

/// 超清源图长边上限；-1 = 全尺寸（内存吃紧机型可改为如 6000 封顶）
const int kHiResMaxEdge = -1;

/// 进入超清模式的缩放阈值（相对屏幕 fit）
const double kHiResZoomThreshold = 1.5;

/// 退出超清模式的下沿迟滞（避免在阈值附近抖动）
const double kHiResZoomHysteresis = 1.25;

/// 是否进入超清模式：缩放超过阈值 && 有已加载的图
class HiResActiveNotifier extends Notifier<bool> {
  bool _armed = false;

  @override
  bool build() {
    ref.listen(zoomScaleProvider, (_, z) => _reconcile(z));
    ref.listen(imageNotifierProvider, (_, _) =>
        _reconcile(ref.read(zoomScaleProvider)));
    return false;
  }

  void _reconcile(double z) {
    if (!_armed && z >= kHiResZoomThreshold) _armed = true;
    if (_armed && z <= kHiResZoomHysteresis) _armed = false;
    final next = _armed && ref.read(imageNotifierProvider).value != null;
    if (next != state) state = next;
  }
}

final hiResActiveProvider = NotifierProvider<HiResActiveNotifier, bool>(
  HiResActiveNotifier.new,
);

/// 超清源图（全尺寸 ui.Image），zoom 超过阈值时惰性生成。
///
/// RAW 复用 [DecodedImageState.decoded] 已解码的全尺寸 raw 零重解码转换；
/// 标准图借引用 imageNotifierProvider 的 ui.Image（不持有所有权，绝不 dispose）。
///
/// full ui.Image 一旦生成就**常驻直到切图**（不因缩回阈值而释放），
/// 保证任意时刻放大都直接复用、不再重新 decodePreview。
class HiResSourceNotifier extends Notifier<ui.Image?> {
  int _gen = 0;
  bool _owned = false; // 当前 state 是否持有所有权
  String? _statePath;

  @override
  ui.Image? build() {
    ref.listen(hiResActiveProvider, (_, _) => _reconcile());
    ref.listen(activeFilePathProvider, (_, _) => _reconcile());
    ref.listen(imageNotifierProvider, (prev, next) {
      // 仅 decoded 字段变化（releaseDecoded 释放 raw）时跳过，避免重复转换
      final p = prev?.value;
      final n = next.value;
      if (p != null &&
          n != null &&
          p.path == n.path &&
          identical(p.uiImage, n.uiImage)) {
        return;
      }
      _reconcile();
    });
    ref.onDispose(_disposeOwned);
    return null;
  }

  Future<void> _reconcile() async {
    final gen = ++_gen;
    if (!ref.read(hiResActiveProvider)) {
      return; // 缩回不释放，full ui.Image 常驻直到切图
    }

    final activePath = ref.read(activeFilePathProvider);
    final st = ref.read(imageNotifierProvider).value;
    if (st == null || st.path != activePath) {
      _setState(null, owned: false);
      return;
    }

    // 已有 full ui.Image 且 path 匹配：直接复用（零重解码）
    if (_owned && state != null && _statePath == activePath) {
      return;
    }

    final decoded = st.decoded;
    if (decoded != null) {
      // RAW 首次加载：已解码全尺寸 raw，直接转换（零重解码）
      final full = await rawToUiImage(decoded, maxEdge: kHiResMaxEdge);
      if (gen != _gen) {
        full.dispose();
        return;
      }
      _setState(full, owned: true, path: activePath);
      // 转换完成，释放 imageNotifierProvider 持有的全尺寸 raw（回 144MB）
      ref.read(imageNotifierProvider.notifier).releaseDecoded();
      return;
    }

    if (RawFormats.isStandard(st.path)) {
      // 标准图：uiImage 已是全尺寸，借引用
      _setState(st.uiImage, owned: false, path: activePath);
      return;
    }

    // RAW 缓存命中：decoded 为 null，重新 decodePreview 取全尺寸 raw
    try {
      final reDecoded = await RawBridge.decodePreview(st.path);
      if (gen != _gen) return;
      final full = await rawToUiImage(reDecoded, maxEdge: kHiResMaxEdge);
      if (gen != _gen) {
        full.dispose();
        return;
      }
      _setState(full, owned: true, path: activePath);
    } catch (e) {
      debugPrint('[HiResSource] re-decode failed: $e');
    }
  }

  void _setState(ui.Image? img, {required bool owned, String? path}) {
    final old = state;
    if (_owned && old != null && !identical(old, img)) {
      _disposeLater(old);
    }
    _owned = owned;
    _statePath = img == null ? null : path;
    state = img;
  }

  void _disposeLater(ui.Image img) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      try {
        img.dispose();
      } catch (_) {}
    });
  }

  void _disposeOwned() {
    final img = state;
    if (_owned && img != null) _disposeLater(img);
  }
}

final hiResSourceProvider = NotifierProvider<HiResSourceNotifier, ui.Image?>(
  HiResSourceNotifier.new,
);
