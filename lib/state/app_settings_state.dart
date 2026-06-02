import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_settings.dart';

final sidecarEnabledProvider = NotifierProvider<SidecarEnabledNotifier, bool>(
  SidecarEnabledNotifier.new,
);
final denoiseParallelismProvider =
    NotifierProvider<DenoiseParallelismNotifier, int>(
      DenoiseParallelismNotifier.new,
    );
final tetherFolderProvider = NotifierProvider<TetherFolderNotifier, String?>(
  TetherFolderNotifier.new,
);

class TetherFolderNotifier extends Notifier<String?> {
  @override
  String? build() {
    AppSettings.getTetherFolder().then((v) {
      if (ref.mounted) state = v;
    });
    return null;
  }

  Future<void> set(String? path) async {
    state = path;
    await AppSettings.setTetherFolder(path);
  }

  Future<void> clear() => set(null);
}

class SidecarEnabledNotifier extends Notifier<bool> {
  static const _key = 'sidecar_enabled';

  @override
  bool build() {
    _load();
    return true; // 默认开
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_key);
    if (v != null) state = v;
  }

  Future<void> set(bool v) async {
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }
}

class DenoiseParallelismNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 4; // 默认 4
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('denoise_parallelism');
    if (v != null) state = v;
  }

  Future<void> set(int v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('denoise_parallelism', v);
  }
}
