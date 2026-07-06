import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 超分辨率预览开关（独立于 srEnabled）
class SrPreviewEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final srPreviewEnabledProvider =
    NotifierProvider<SrPreviewEnabledNotifier, bool>(
      SrPreviewEnabledNotifier.new,
    );
