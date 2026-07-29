import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/crop_params.dart';
import '../../render/full_pipeline_renderer.dart';
import '../../render/thumbnail_renderer.dart';
import '../providers.dart';
import 'history_entry.dart';

/// History Brush 快照图像
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

/// 历史面板可视化层——条目生成/防抖/隔离由 [HistoryNotifier] 负责
///
/// 仅负责：同步 panelEntries、UI 选中状态、revertTo / brushSource 操作
class HistoryPanelNotifier extends Notifier<HistoryPanelState> {
  @override
  HistoryPanelState build() {
    // 从 HistoryNotifier 读取初始 entry 列表
    final initial = ref.read(historyNotifierProvider);
    final initialState = HistoryPanelState(entries: initial.panelEntries);

    ref.listen(historyNotifierProvider, (prev, next) {
      if (prev?.panelVersion == next.panelVersion) return;
      final isReset = next.panelVersion == 0;
      state = state.copyWith(
        entries: next.panelEntries,
        clearSelected: isReset,
        clearBrushSource: isReset,
      );
    });

    return initialState;
  }

  // ── 公开操作 ──

  void revertTo(int index) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    ref
        .read(historyNotifierProvider.notifier)
        .applyWithoutHistory(entry.params);
    state = state.copyWith(selectedIndex: index);
  }

  Future<void> selectBrushSource(int index) async {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];

    final snapshot = await _renderSnapshot(entry.params);
    if (snapshot == null) return;

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
    final sourceImage = ref.read(imageNotifierProvider).value?.uiImage;
    if (sourceImage == null) return null;

    final snapshotParams = params.copyWith(crop: CropParams.identity);
    final safe = sourceImage.clone();
    try {
      final result = await FullPipelineRenderer.renderFromRef(
        ref,
        sourceImage: safe,
        params: snapshotParams,
        targetWidth: sourceImage.width,
        targetHeight: sourceImage.height,
        includeBrushLayers: true,
      );
      return result?.finalImage;
    } catch (_) {
      return null;
    } finally {
      safe.dispose();
    }
  }

  void clear() {
    // 清空 HistoryNotifier 中的面板条目
    ref.read(historyNotifierProvider.notifier).clearPanel();
    // 清空缩略图 + 画笔快照
    ref.read(thumbnailRendererProvider.notifier).removeNamespace('history');
    final oldSnapshot = historyBrushSnapshot.value;
    historyBrushSnapshot.value = null;
    oldSnapshot?.dispose();
    // 重置面板 UI 状态（包括 selectedIndex / brushSourceIndex）
    state = const HistoryPanelState();
  }

  /// 同步释放画笔快照 ValueNotifier
  void dispose() {
    final old = historyBrushSnapshot.value;
    historyBrushSnapshot.value = null;
    old?.dispose();
  }
}

final historyPanelProvider =
    NotifierProvider<HistoryPanelNotifier, HistoryPanelState>(
      HistoryPanelNotifier.new,
    );
