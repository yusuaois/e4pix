import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/watermark_config.dart';

class WatermarkNotifier extends Notifier<WatermarkConfig> {
  @override
  WatermarkConfig build() => const WatermarkConfig();

  void update(WatermarkConfig config) => state = config;

  void toggle() => state = state.copyWith(enabled: !state.enabled);

  void reset() => state = const WatermarkConfig();
}

final watermarkConfigProvider =
    NotifierProvider<WatermarkNotifier, WatermarkConfig>(WatermarkNotifier.new);
