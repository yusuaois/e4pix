import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models/adjustment_params.dart';
import '../core/models/tethered_shot.dart';
import '../services/tether_watcher.dart';
import 'image_state.dart';

// ============================================================================
// Tether 会话（监听器 + 路径）—— 不存在则代表未联机
// ============================================================================
@immutable
class TetherSession {
  final TetherWatcher watcher;
  final String watchPath;
  final DateTime? lastShotAt;

  const TetherSession({
    required this.watcher,
    required this.watchPath,
    this.lastShotAt,
  });

  TetherSession copyWith({DateTime? lastShotAt}) => TetherSession(
    watcher: watcher,
    watchPath: watchPath,
    lastShotAt: lastShotAt ?? this.lastShotAt,
  );
}

class TetherSessionNotifier extends Notifier<TetherSession?> {
  StreamSubscription<File>? _sub;

  @override
  TetherSession? build() {
    ref.onDispose(() async {
      await _sub?.cancel();
      await state?.watcher.dispose();
    });
    return null;
  }

  Future<void> start(String watchPath) async {
    if (state != null) return;
    final watcher = TetherWatcher(watchPath);
    await watcher.start();

    _sub = watcher.onShot.listen((file) {
      ref.read(shotsNotifierProvider.notifier).onNewShot(file);
      // 同步 lastShotAt
      final cur = state;
      if (cur != null) state = cur.copyWith(lastShotAt: DateTime.now());
    });

    state = TetherSession(watcher: watcher, watchPath: watchPath);
  }

  Future<void> stop() async {
    final session = state;
    await _sub?.cancel();
    _sub = null;
    state = null;
    await session?.watcher.dispose();
    ref.read(shotsNotifierProvider.notifier).clear();
    ref.read(activeShotPathProvider.notifier).set(null);
  }
}

final tetherSessionNotifierProvider =
    NotifierProvider<TetherSessionNotifier, TetherSession?>(
      TetherSessionNotifier.new,
    );

// ============================================================================
// Shots list
// ============================================================================
class ShotsNotifier extends Notifier<List<TetheredShot>> {
  bool _isDisposed = false; // 添加一个标志位

  @override
  List<TetheredShot> build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true; // 销毁时标记为 true
      for (final s in state) {
        try {
          s.disposeThumbnail();
        } catch (_) {}
      }
    });
    return const [];
  }

  Future<void> onNewShot(File file) async {
    final preserve = ref.read(preserveParamsProvider);
    final activePath = ref.read(activeShotPathProvider);

    TetheredShot? activeShot;
    if (activePath != null) {
      for (final s in state) {
        if (s.path == activePath) {
          activeShot = s;
          break;
        }
      }
    }

    final inherited = preserve && activeShot != null
        ? activeShot.params
        : AdjustmentParams.neutral;

    final shot = TetheredShot(
      path: file.path,
      filename: p.basename(file.path),
      detectedAt: DateTime.now(),
      params: inherited,
    );

    // 同步添加新照片到列表
    state = [...state, shot];

    // 自动切到新 shot
    ref.read(activeShotPathProvider.notifier).set(shot.path);
    ref.read(activeFilePathProvider.notifier).set(shot.path);

    // 异步加载缩略图
    final loaded = await TetheredShot.loadWithThumbnail(shot);

    if (_isDisposed) {
      loaded.disposeThumbnail();
      return;
    }

    // 替换包含缩略图的实例，触发 UI 刷新
    state = [for (final s in state) s.path == shot.path ? loaded : s];
  }

  void updateParams(String shotPath, AdjustmentParams newParams) {
    state = [
      for (final s in state)
        if (s.path == shotPath) s.copyWith(params: newParams) else s,
    ];
  }

  void updateAllParams(AdjustmentParams newParams) {
    state = [for (final s in state) s.copyWith(params: newParams)];
  }

  void clear() {
    for (final s in state) {
      s.disposeThumbnail();
    }
    state = const [];
  }
}

final shotsNotifierProvider =
    NotifierProvider<ShotsNotifier, List<TetheredShot>>(ShotsNotifier.new);

// Active shot
class ActiveShotPathNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? path) => state = path;
}

final activeShotPathProvider =
    NotifierProvider<ActiveShotPathNotifier, String?>(
      ActiveShotPathNotifier.new,
    );

final activeShotProvider = Provider<TetheredShot?>((ref) {
  final path = ref.watch(activeShotPathProvider);
  if (path == null) return null;
  final shots = ref.watch(shotsNotifierProvider);
  for (final s in shots) {
    if (s.path == path) return s;
  }
  return null;
});

// 同时更新 activeShotPath 和 activeFilePath
final selectShotProvider = Provider<void Function(TetheredShot)>((ref) {
  return (shot) {
    ref.read(activeShotPathProvider.notifier).set(shot.path);
    ref.read(activeFilePathProvider.notifier).set(shot.path);
  };
});

// Preserve params toggle
class PreserveParamsNotifier extends Notifier<bool> {
  @override
  bool build() => true; // 默认 preserve 模式

  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final preserveParamsProvider = NotifierProvider<PreserveParamsNotifier, bool>(
  PreserveParamsNotifier.new,
);
