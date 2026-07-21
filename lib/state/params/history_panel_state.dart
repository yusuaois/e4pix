import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../render/render_engine.dart';
import '../../render/thumbnail_renderer.dart';
import '../../utils/debouncer.dart';
import '../providers.dart';
import 'history_entry.dart';

/// History Brush 快照图像 —— 全局 ValueNotifier，无需 Riverpod Ref 即可读取
final historyBrushSnapshot = ValueNotifier<ui.Image?>(null);

@immutable
class HistoryPanelState {
  final List<HistoryEntry> entries;
  final int? selectedIndex;
  final int? brushSourceIndex;

  const HistoryPanelState({
    this.entries = const [],
    this.selectedIndex,
    this.brushSourceIndex,
  });

  HistoryPanelState copyWith({
    List<HistoryEntry>? entries,
    int? selectedIndex,
    bool clearSelected = false,
    int? brushSourceIndex,
    bool clearBrushSource = false,
  }) => HistoryPanelState(
    entries: entries ?? this.entries,
    selectedIndex: clearSelected ? null : (selectedIndex ?? this.selectedIndex),
    brushSourceIndex: clearBrushSource
        ? null
        : (brushSourceIndex ?? this.brushSourceIndex),
  );
}

class HistoryPanelNotifier extends Notifier<HistoryPanelState> {
  static const int _maxEntries = 50;
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  final _debouncer = Debouncer();

  bool _isReverting = false;
  bool _disposed = false;

  int _counter = 0;

  @override
  HistoryPanelState build() {
    // 参数变化 → debounce 捕获
    ref.listen<AdjustmentParams>(currentParamsNotifierProvider, (prev, next) {
      if (_disposed || _isReverting) return;
      if (prev == next) return;
      _scheduleParamCapture(prev, next);
    });

    ref.onDispose(() {
      _disposed = true;
      _debouncer.cancel();
    });

    return const HistoryPanelState();
  }

  // ── 参数变化捕获 ──

  void _scheduleParamCapture(AdjustmentParams? prev, AdjustmentParams next) {
    if (prev == null) return;
    _debouncer.run(_debounceDelay, () => _captureFromParams(prev, next));
  }

  void _captureFromParams(AdjustmentParams prev, AdjustmentParams next) {
    if (_disposed) return;
    final label = _diffLabel(prev, next);
    final id = 'param_${_counter++}_${DateTime.now().millisecondsSinceEpoch}';
    final entry = HistoryEntry(
      id: id,
      label: label,
      params: next,
      timestamp: DateTime.now(),
    );
    _appendEntry(entry);
    ref
        .read(thumbnailRendererProvider.notifier)
        .requestFull('history', entry.id, entry.params);
  }

  String _diffLabel(AdjustmentParams prev, AdjustmentParams next) {
    final changes = <String>[];
    if (prev.exposure != next.exposure) changes.add('Exposure');
    if (prev.contrast != next.contrast) changes.add('Contrast');
    if (prev.highlights != next.highlights) changes.add('Highlights');
    if (prev.shadows != next.shadows) changes.add('Shadows');
    if (prev.whites != next.whites) changes.add('Whites');
    if (prev.blacks != next.blacks) changes.add('Blacks');
    if (prev.temperature != next.temperature) changes.add('Temperature');
    if (prev.vibrance != next.vibrance) changes.add('Vibrance');
    if (prev.saturation != next.saturation) changes.add('Saturation');
    if (prev.sharpenAmount != next.sharpenAmount) changes.add('Sharpen');
    if (prev.denoiseLuma != next.denoiseLuma ||
        prev.denoiseColor != next.denoiseColor) {
      changes.add('Denoise');
    }
    return changes.isEmpty ? 'Adjustment' : changes.join(', ');
  }

  // ── 笔画结束捕获（外部调用）──

  void captureStroke(String label) {
    if (_disposed) return;
    final params = ref.read(currentParamsNotifierProvider);
    final id = 'stroke_${_counter++}_${DateTime.now().millisecondsSinceEpoch}';
    final entry = HistoryEntry(
      id: id,
      label: label,
      params: params,
      timestamp: DateTime.now(),
    );
    _appendEntry(entry);
    ref
        .read(thumbnailRendererProvider.notifier)
        .requestFull('history', entry.id, entry.params);
  }

  // ── 条目管理 ──

  void _appendEntry(HistoryEntry entry) {
    final newEntries = [...state.entries, entry];
    // 超过上限时移除最旧条目
    while (newEntries.length > _maxEntries) {
      newEntries.removeAt(0);
    }
    state = state.copyWith(entries: newEntries, clearSelected: true);
  }

  // ── 公开操作 ──

  void revertTo(int index) {
    if (_disposed || index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];

    _isReverting = true;
    ref
        .read(historyNotifierProvider.notifier)
        .applyWithoutHistory(entry.params);
    state = state.copyWith(selectedIndex: index);
    Future.microtask(() {
      _isReverting = false;
    });
  }

  Future<void> selectBrushSource(int index) async {
    if (_disposed || index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];

    final snapshot = await _renderSnapshot(entry.params);
    if (_disposed) {
      snapshot?.dispose();
      return;
    }

    final old = historyBrushSnapshot.value;
    historyBrushSnapshot.value = snapshot;
    old?.dispose();

    state = state.copyWith(brushSourceIndex: index);
  }

  void clearBrushSource() {
    final old = historyBrushSnapshot.value;
    historyBrushSnapshot.value = null;
    old?.dispose();
    state = state.copyWith(clearBrushSource: true);
  }

  Future<ui.Image?> _renderSnapshot(AdjustmentParams params) async {
    final program = ref.read(shaderProgramProvider).value;
    final sourceImage = ref.read(imageNotifierProvider).value?.uiImage;
    if (program == null || sourceImage == null) return null;

    final cleanParams = params.copyWith(
      locals: const [],
      sharpenAmount: 0,
      denoiseLuma: 0,
      denoiseColor: 0,
    );

    try {
      return await RenderEngine.renderToImage(
        program: program,
        sourceImage: sourceImage,
        params: cleanParams,
        targetWidth: sourceImage.width,
        targetHeight: sourceImage.height,
      );
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _debouncer.cancel();
    final oldSnapshot = historyBrushSnapshot.value;
    historyBrushSnapshot.value = null;
    oldSnapshot?.dispose();
    ref.read(thumbnailRendererProvider.notifier).removeNamespace('history');
    state = const HistoryPanelState();
  }
}

final historyPanelProvider =
    NotifierProvider<HistoryPanelNotifier, HistoryPanelState>(
      HistoryPanelNotifier.new,
    );
