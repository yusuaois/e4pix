import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 预览质量档位
enum PreviewQuality { low, medium, high }

extension PreviewQualitySpec on PreviewQuality {
  (int, int) edges({required bool isVertical}) {
    switch (this) {
      case PreviewQuality.low:
        return isVertical ? (800, 400) : (1000, 500);
      case PreviewQuality.medium:
        return isVertical ? (1600, 600) : (2400, 800);
      case PreviewQuality.high:
        return isVertical ? (3200, 1000) : (5000, 1600);
    }
  }
}

class PreviewQualityNotifier extends Notifier<PreviewQuality> {
  static const _key = 'preview_quality';

  @override
  PreviewQuality build() {
    _load();
    return PreviewQuality.medium;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    final v = PreviewQuality.values.where((e) => e.name == s).firstOrNull;
    if (v != null) state = v;
  }

  Future<void> set(PreviewQuality q) async {
    state = q;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, q.name);
  }
}

final previewQualityProvider =
    NotifierProvider<PreviewQualityNotifier, PreviewQuality>(
      PreviewQualityNotifier.new,
    );

/// 默认导出 JPEG 质量
class ExportQualityNotifier extends Notifier<int> {
  static const _key = 'export_jpeg_quality';

  @override
  int build() {
    _load();
    return 95;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt(_key);
    if (v != null) state = v.clamp(50, 100);
  }

  Future<void> set(int q) async {
    final v = q.clamp(50, 100);
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_key, v);
  }
}

final exportQualityProvider = NotifierProvider<ExportQualityNotifier, int>(
  ExportQualityNotifier.new,
);
