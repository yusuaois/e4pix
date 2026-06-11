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

  // O(1) path→shot 查找缓存，随每次 state 变更同步维护
  final Map<String, TetheredShot> _byPath = {};

  /// O(1) 按路径查找 shot，不存在返回 null
  TetheredShot? shotByPath(String path) => _byPath[path];

  /// 路径 → shot 映射
  Map<String, TetheredShot> get pathMap => Map.unmodifiable(_byPath);

  void _rebuildCache(List<TetheredShot> list) {
    _byPath.clear();
    for (final s in list) {
      _byPath[s.path] = s;
    }
  }

  @override
  List<TetheredShot> build() {
    _isDisposed = false;
    _byPath.clear();
    ref.onDispose(() {
      _isDisposed = true;
      for (final s in _byPath.values) {
        try {
          s.disposeThumbnail();
        } catch (_) {}
      }
      _byPath.clear();
    });
    return const [];
  }

  void _setState(List<TetheredShot> next) {
    _rebuildCache(next);
    state = next;
  }

  List<TetheredShot> _replaceOne(List<TetheredShot> list, TetheredShot shot) {
    final result = List<TetheredShot>.of(list);
    for (int i = 0; i < result.length; i++) {
      if (result[i].path == shot.path) {
        result[i] = shot;
        break;
      }
    }
    return result;
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
      final existing = state
          .where((s) => RawFormats.baseKey(s.path) == base)
          .toList();
      if (isRaw) {
        final standardDupes = existing
            .where((s) => RawFormats.isStandard(s.path))
            .toList();
        if (standardDupes.isNotEmpty) {
          for (final dup in standardDupes) {
            dup.disposeThumbnail();
          }
          final filtered = state
              .where((s) => !standardDupes.contains(s))
              .toList();
          _setState(filtered);
        }
      } else {
        if (existing.any((s) => RawFormats.isRaw(s.path))) {
          return; // RAW 已在，丢弃 JPG
        }
      }
    }

    final preserve = ref.read(preserveParamsProvider);
    final activePath = ref.read(activeShotPathProvider);
    final activeShot = activePath != null ? _byPath[activePath] : null;

    final inherited = preserve && activeShot != null
        ? activeShot.params
        : AdjustmentParams.neutral;

    var shot = TetheredShot(
      path: file.path,
      filename: p.basename(file.path),
      detectedAt: DateTime.now(),
      params: inherited,
    );
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
    _setState([...state, shot]);

    ref.read(activeShotPathProvider.notifier).set(shot.path);
    ref.read(activeFilePathProvider.notifier).set(shot.path);

    final loaded = await TetheredShot.loadWithThumbnail(shot);

    if (_isDisposed) {
      loaded.disposeThumbnail();
      return;
    }

    _setState(_replaceOne(state, loaded));
    ref.read(aiAutoNotifierProvider.notifier).onNewShotArrived(shot.path);
  }

  Future<void> addFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final mode = ref.read(importModeProvider);
    paths = filterByImportMode(paths, mode);
    if (paths.isEmpty) return;

    final fresh = paths.where((p) => !_byPath.containsKey(p)).toList();
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
    _setState([...state, ...newShots]);

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
      if (_byPath.containsKey(shot.path)) {
        _setState(_replaceOne(state, loaded));
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
    _setState(updated);
  }

  /// 单张参数更新
  void updateParams(String shotPath, AdjustmentParams newParams) {
    final entry = _byPath[shotPath];
    if (entry == null) return;
    _setState(_replaceOne(state, entry.copyWith(params: newParams)));
  }

  /// 全量覆盖
  void updateAllParams(AdjustmentParams newParams) {
    final updated = List<TetheredShot>.of(state);
    for (int i = 0; i < updated.length; i++) {
      updated[i] = updated[i].copyWith(params: newParams);
    }
    _setState(updated);
  }

  void updateRating(String shotPath, int rating) {
    final entry = _byPath[shotPath];
    if (entry == null) return;
    _setState(_replaceOne(state, entry.copyWith(rating: rating.clamp(0, 5))));
  }

  void updateFlag(String shotPath, ShotFlag flag) {
    final entry = _byPath[shotPath];
    if (entry == null) return;
    _setState(_replaceOne(state, entry.copyWith(flag: flag)));
  }

  void clear() {
    for (final s in _byPath.values) {
      s.disposeThumbnail();
    }
    _setState(const []);
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
  ref.watch(shotsNotifierProvider);
  return ref.read(shotsNotifierProvider.notifier).shotByPath(path);
});

final shotByPathProvider = Provider.family<TetheredShot?, String>((ref, path) {
  ref.watch(shotsNotifierProvider);
  return ref.read(shotsNotifierProvider.notifier).shotByPath(path);
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

final importModeProvider = NotifierProvider<ImportModeNotifier, ImportMode>(
  ImportModeNotifier.new,
);

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
