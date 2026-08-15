import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// hi-res 显示的 displaySize（BoxFit.contain 后的逻辑尺寸）。
///
/// 由 `preview_area` 在布局时写入（microtask 延迟，避免 build 期间改 provider），
/// 供 `HiResRenderNotifier` 按需选层级（`selectPyramidLevel` 需要 displaySize+dpr）。
class HiResDisplaySizeNotifier extends Notifier<Size?> {
  @override
  Size? build() => null;
  void set(Size? v) => state = v;
}

final hiResDisplaySizeProvider =
    NotifierProvider<HiResDisplaySizeNotifier, Size?>(
      HiResDisplaySizeNotifier.new,
    );
