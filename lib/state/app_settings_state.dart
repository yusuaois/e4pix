import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_settings.dart';

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

final tetherFolderProvider =
    NotifierProvider<TetherFolderNotifier, String?>(TetherFolderNotifier.new);