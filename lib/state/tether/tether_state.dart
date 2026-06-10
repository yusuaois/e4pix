import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/raw_formats.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/models/sync_options.dart';
import '../../core/models/tethered_shot.dart';
import '../../services/notifications/tether_notification_service.dart';
import '../../services/export/sidecar_service.dart';
import '../../services/tether/tether_watcher.dart';
import '../providers.dart';

// Tether 会话
@immutable
class TetherSession {
  final TetherWatcher watcher;
  final String watchPath;
  final DateTime? lastShotAt;
  final bool suppressNotification;

  const TetherSession({
    required this.watcher,
    required this.watchPath,
    this.lastShotAt,
    this.suppressNotification = false,
  });

  TetherSession copyWith({DateTime? lastShotAt}) => TetherSession(
    watcher: watcher,
    watchPath: watchPath,
    lastShotAt: lastShotAt ?? this.lastShotAt,
    suppressNotification: suppressNotification,
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

  Future<void> start(
    String watchPath, {
    bool suppressNotification = false,
  }) async {
    if (state != null) return;
    final watcher = TetherWatcher(watchPath);
    await watcher.start();

    _sub = watcher.onShot.listen((file) {
      ref.read(shotsNotifierProvider.notifier).onNewShot(file);
      // 同步 lastShotAt
      final cur = state;
      if (cur != null) state = cur.copyWith(lastShotAt: DateTime.now());
    });

    state = TetherSession(
      watcher: watcher,
      watchPath: watchPath,
      suppressNotification: suppressNotification,
    );

    // 通知
    if (!suppressNotification) {
      TetherNotificationService.instance.showWatcherOngoing(
        watchPath: watchPath,
      );
    }
  }

  Future<void> stop() async {
    final session = state;
    await _sub?.cancel();
    _sub = null;
    state = null;
    await session?.watcher.dispose();

    // 销毁通知
    if (session != null && !session.suppressNotification) {
      TetherNotificationService.instance.dismissWatcherOngoing();
    }
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
    final mode = ref.read(importModeProvider);
    final path = file.path;

    // 模式过滤 / 去重
    if (mode == ImportMode.rawOnly && !RawFormats.isRaw(path)) {
      return; // 仅 RAW，标准图直接忽略
    }
    if (!RawFormats.isSupported(path)) return; // 非图片忽略

    if (mode == ImportMode.rawPriority) {
      final base = RawFormats.baseKey(path);
      final isRaw = RawFormats.isRaw(path);
      // 已存在的同基名 shot
      final existing = state
          .where((s) => RawFormats.baseKey(s.path) == base)
          .toList();
      if (isRaw) {
        // 新来 RAW：移除同名的标准图（RAW 优先）
        final standardDupes = existing
            .where((s) => RawFormats.isStandard(s.path))
            .toList();
        if (standardDupes.isNotEmpty) {
          for (final dup in standardDupes) {
            dup.disposeThumbnail();
          }
          state = state.where((s) => !standardDupes.contains(s)).toList();
          // 如果被移除的是当前激活图，激活新 RAW
        }
      } else {
        // 新来标准图：若已有同名 RAW，跳过
        if (existing.any((s) => RawFormats.isRaw(s.path))) {
          return; // RAW 已在，丢弃 JPG
        }
      }
    }

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

    var shot = TetheredShot(
      path: file.path,
      filename: p.basename(file.path),
      detectedAt: DateTime.now(),
      params: inherited,
    );
    // 读 sidecar
    if (ref.read(sidecarEnabledProvider)) {
      final data = await SidecarService.read(file.path);
      if (data != null) {
        shot = shot.copyWith(
          params: data.params,
          rating: data.rating,
          flag: data.flag,
        );
      }
    }
    state = [...state, shot];

    ref.read(activeShotPathProvider.notifier).set(shot.path);
    ref.read(activeFilePathProvider.notifier).set(shot.path);

    final loaded = await TetheredShot.loadWithThumbnail(shot);

    if (_isDisposed) {
      loaded.disposeThumbnail();
      return;
    }

    state = [for (final s in state) s.path == shot.path ? loaded : s];
    ref.read(aiAutoNotifierProvider.notifier).onNewShotArrived(shot.path);
  }

  Future<void> addFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final mode = ref.read(importModeProvider);
    paths = filterByImportMode(paths, mode);
    if (paths.isEmpty) return;

    final existing = state.map((s) => s.path).toSet();
    final fresh = paths.where((p) => !existing.contains(p)).toList();
    if (fresh.isEmpty) {
      ref.read(activeShotPathProvider.notifier).set(paths.first);
      ref.read(activeFilePathProvider.notifier).set(paths.first);
      return;
    }

    final sidecarOn = ref.read(sidecarEnabledProvider);

    final newShots = <TetheredShot>[];
    for (final path in fresh) {
      var shot = TetheredShot(
        path: path,
        filename: p.basename(path),
        detectedAt: DateTime.now(),
        params: AdjustmentParams.neutral,
      );
      // 读 sidecar
      if (sidecarOn) {
        final data = await SidecarService.read(path);
        if (data != null) {
          shot = shot.copyWith(
            params: data.params,
            rating: data.rating,
            flag: data.flag,
          );
        }
      }
      newShots.add(shot);
    }
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

  void syncParamsToPaths(
    Set<String> paths,
    AdjustmentParams src,
    Set<SyncItem> items,
  ) {
    final updated = List<TetheredShot>.of(state);
    for (int i = 0; i < updated.length; i++) {
      if (paths.contains(updated[i].path)) {
        updated[i] = updated[i].copyWith(
          params: mergeParams(updated[i].params, src, items),
        );
      }
    }
    state = updated;
  }

  /// 单张参数更新
  void updateParams(String shotPath, AdjustmentParams newParams) {
    final idx = state.indexWhere((s) => s.path == shotPath);
    if (idx < 0) return;
    final updated = List<TetheredShot>.of(state);
    updated[idx] = updated[idx].copyWith(params: newParams);
    state = updated;
  }

  /// 全量覆盖
  void updateAllParams(AdjustmentParams newParams) {
    final updated = List<TetheredShot>.of(state);
    for (int i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(params: newParams);
    }
    state = updated;
  }

  void updateRating(String shotPath, int rating) {
    final r = rating.clamp(0, 5);
    final idx = state.indexWhere((s) => s.path == shotPath);
    if (idx < 0) return;
    final updated = List<TetheredShot>.of(state);
    updated[idx] = updated[idx].copyWith(rating: r);
    state = updated;
  }

  void updateFlag(String shotPath, ShotFlag flag) {
    final idx = state.indexWhere((s) => s.path == shotPath);
    if (idx < 0) return;
    final updated = List<TetheredShot>.of(state);
    updated[idx] = updated[idx].copyWith(flag: flag);
    state = updated;
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

// ── 导入模式 ──

enum ImportMode { rawPriority, rawOnly, all }

class ImportModeNotifier extends Notifier<ImportMode> {
  @override
  ImportMode build() {
    _load();
    return ImportMode.rawPriority;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('import_mode');
    if (v != null) {
      state = ImportMode.values.firstWhere(
        (e) => e.name == v,
        orElse: () => ImportMode.rawPriority,
      );
    }
  }

  Future<void> set(ImportMode m) async {
    state = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('import_mode', m.name);
  }
}

final importModeProvider =
    NotifierProvider<ImportModeNotifier, ImportMode>(ImportModeNotifier.new);

/// 按导入模式过滤 + 去重文件列表
List<String> filterByImportMode(List<String> paths, ImportMode mode) {
  switch (mode) {
    case ImportMode.rawOnly:
      return paths.where(RawFormats.isRaw).toList();
    case ImportMode.all:
      return paths.where(RawFormats.isSupported).toList();
    case ImportMode.rawPriority:
      final supported = paths.where(RawFormats.isSupported).toList();
      final rawBases = <String>{};
      for (final pth in supported) {
        if (RawFormats.isRaw(pth)) rawBases.add(RawFormats.baseKey(pth));
      }
      return supported.where((pth) {
        if (RawFormats.isRaw(pth)) return true;
        return !rawBases.contains(RawFormats.baseKey(pth));
      }).toList();
  }
}
