import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDynamicKey = 'theme_dynamic_color';
const _kSeedKey = 'theme_seed_color';
const int kDefaultSeed = 0xFF6B5BFF;

class DynamicColorEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool(_kDynamicKey);
      if (v != null && ref.mounted) state = v;
    });
    return true;
  }

  Future<void> set(bool v) async {
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDynamicKey, v);
  }
}

final dynamicColorEnabledProvider =
    NotifierProvider<DynamicColorEnabledNotifier, bool>(
      DynamicColorEnabledNotifier.new,
    );

class SeedColorNotifier extends Notifier<int> {
  @override
  int build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getInt(_kSeedKey);
      if (v != null && ref.mounted) state = v;
    });
    return kDefaultSeed;
  }

  Future<void> set(int argb) async {
    state = argb;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSeedKey, argb);
  }
}

final seedColorProvider =
    NotifierProvider<SeedColorNotifier, int>(SeedColorNotifier.new);