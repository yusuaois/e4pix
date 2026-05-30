import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/models/adjustment_params.dart';
import '../core/models/tethered_shot.dart';
import '../services/tether_watcher.dart';
import 'ai_auto_state.dart';
import 'image_state.dart';

// Tether 会话
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

// Shots list
class ShotsNotifier extends Notifier<List<TetheredShot>> {
  bool _isDisposed = false;

  @override
  List<TetheredShot> build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
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

    state = [...state, shot];

    ref.read(activeShotPathProvider.notifier).set(shot.path);
    ref.read(activeFilePathProvider.notifier).set(shot.path);

    final loaded = await TetheredShot.loadWithThumbnail(shot);

    if (_isDisposed) {
      loaded.disposeThumbnail();
      return;
    }

    state = [for (final s in state) s.path == shot.path ? loaded : s];
    ref.read(aiAutoNotifierProvider.notifier).onNewShotArrived();
  }

  Future<void> addFiles(List<String> paths) async {
    if (paths.isEmpty) return;

    final existing = state.map((s) => s.path).toSet();
    final fresh = paths.where((p) => !existing.contains(p)).toList();
    if (fresh.isEmpty) {
      ref.read(activeShotPathProvider.notifier).set(paths.first);
      ref.read(activeFilePathProvider.notifier).set(paths.first);
      return;
    }

    final newShots = [
      for (final path in fresh)
        TetheredShot(
          path: path,
          filename: p.basename(path),
          detectedAt: DateTime.now(),
          params: AdjustmentParams.neutral,
        ),
    ];
    state = [...state, ...newShots];

    final first = newShots.first;
    ref.read(activeShotPathProvider.notifier).set(first.path);
    ref.read(activeFilePathProvider.notifier).set(first.path);

    for (final shot in newShots) {
      if (_isDisposed) return;
      final loaded = await TetheredShot.loadWithThumbnail(shot);
      if (_isDisposed) {
        loaded.disposeThumbnail();
        return;
      }
      if (state.any((s) => s.path == shot.path)) {
        state = [for (final s in state) s.path == shot.path ? loaded : s];
      } else {
        loaded.disposeThumbnail();
      }
    }
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

  void updateRating(String shotPath, int rating) {
    final r = rating.clamp(0, 5);
    state = [
      for (final s in state)
        if (s.path == shotPath) s.copyWith(rating: r) else s,
    ];
  }

  void updateFlag(String shotPath, ShotFlag flag) {
    state = [
      for (final s in state)
        if (s.path == shotPath) s.copyWith(flag: flag) else s,
    ];
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

// 更新 activeShotPath 和 activeFilePath
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
