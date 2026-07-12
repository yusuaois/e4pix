import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';
import '../core/models/crop_params.dart';
import '../render/brush_layer_provider.dart';
import '../state/providers.dart';

import 'clone_stamp/clone_stamp_layer.dart';
import 'clone_stamp/clone_stamp_overlay.dart';
import 'healing/healing_layer.dart';
import 'healing/healing_overlay.dart';
import 'spot_heal/spot_heal_layer.dart';
import 'spot_heal/spot_heal_overlay.dart';
import 'dodge_burn/dodge_burn_layer.dart';
import 'dodge_burn/dodge_burn_overlay.dart';
import 'sponge/sponge_layer.dart';
import 'sponge/sponge_overlay.dart';
import 'history_brush/history_brush_layer.dart';
import 'history_brush/history_brush_overlay.dart';
import 'shared/stamp/stamp_mark.dart';
import 'clone_stamp/clone_stamp_model.dart';
import 'healing/healing_model.dart';
import 'spot_heal/spot_heal_model.dart';
import 'dodge_burn/dodge_burn_model.dart';
import 'sponge/sponge_model.dart';
import 'history_brush/history_brush_model.dart';
import 'clone_stamp/clone_stamp_state.dart';
import 'healing/healing_state.dart';
import 'spot_heal/spot_heal_state.dart';
import 'dodge_burn/dodge_burn_state.dart';
import 'sponge/sponge_state.dart';
import 'history_brush/history_brush_state.dart';
import 'clone_stamp/clone_stamp_section.dart';
import 'healing/healing_section.dart';
import 'spot_heal/spot_heal_section.dart';
import 'dodge_burn/dodge_burn_section.dart';
import 'sponge/sponge_section.dart';
import 'history_brush/history_brush_section.dart';

/// overlay 工厂的参数打包
class OverlayFactoryParams {
  final WidgetRef ref;
  final Size imageDisplaySize;
  final CropParams crop;
  final int sourceWidth;
  final int sourceHeight;
  final ui.Image sourceImage;

  const OverlayFactoryParams({
    required this.ref,
    required this.imageDisplaySize,
    required this.crop,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceImage,
  });
}

/// Self-describing metadata for a brush tool.
///
/// Integration points (shader loading, pass config, layer registry,
/// warmup, UI panels) iterate over [brushManifests] instead of having
/// per-brush code.
class BrushManifest {
  final String id;
  final String titleKey;
  final IconData icon;
  final String shaderAsset;
  final bool Function(AdjustmentParams) hasMarks;
  final BrushLayerProvider Function(ui.FragmentProgram program) layerFactory;
  final int Function(AdjustmentParams params) hashMarks;
  final DevelopTool tool;

  /// overlay 工厂：返回 overlay widget，或 null 表示不活跃
  final Widget? Function(OverlayFactoryParams params) overlayFactory;

  /// 从 JSON 列表反序列化 marks（用于 AdjustmentParams.fromJson）
  final List<StampMark> Function(List<Map<String, dynamic>> json)?
  marksFromJson;

  /// 停用画笔回调（切换工具时自动退出）
  final void Function(WidgetRef ref) deactivate;

  /// UI 面板工厂（参数面板中显示画笔设置）
  final Widget Function(
    AdjustmentParams params,
    ValueChanged<AdjustmentParams> onChanged,
  )
  sectionFactory;

  const BrushManifest({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.shaderAsset,
    required this.hasMarks,
    required this.layerFactory,
    required this.hashMarks,
    required this.tool,
    required this.overlayFactory,
    this.marksFromJson,
    required this.deactivate,
    required this.sectionFactory,
  });
}

/// 所有笔刷工具的唯一数据源
///
/// 注册顺序决定 Compose 层级（首个=底层）和面板 tab/rail 顺序
final brushManifests = <BrushManifest>[
  // --- 图章 ---
  BrushManifest(
    id: 'spot_removal',
    titleKey: 'spotRemoveTitle',
    icon: Icons.healing,
    shaderAsset: 'assets/shaders/brushes/spot_remove.frag',
    hasMarks: _hasSpots,
    layerFactory: _makeSpotRemovalLayer,
    hashMarks: _hashSpots,
    tool: DevelopTool.spotRemove,
    overlayFactory: _makeSpotRemovalOverlay,
    marksFromJson: (list) => list.map((j) => SpotMark.fromJson(j)).toList(),
    deactivate: (ref) => ref
        .read(spotRemoveStateProvider.notifier)
        .setMode(SpotRemoveMode.inactive),
    sectionFactory: (p, oc) => SpotRemoveSection(params: p, onChanged: oc),
  ),
  // --- 修复画笔 ---
  BrushManifest(
    id: 'healing',
    titleKey: 'healingTitle',
    icon: Icons.auto_fix_high,
    shaderAsset: 'assets/shaders/brushes/healing.frag',
    hasMarks: _hasHealingMarks,
    layerFactory: _makeHealingLayer,
    hashMarks: _hashHealingMarks,
    tool: DevelopTool.healing,
    overlayFactory: _makeHealingOverlay,
    marksFromJson: (list) => list.map((j) => HealingMark.fromJson(j)).toList(),
    deactivate: (ref) =>
        ref.read(healingStateProvider.notifier).setMode(HealingMode.inactive),
    sectionFactory: (p, oc) => HealingSection(params: p, onChanged: oc),
  ),
  // --- 污点修复 ---
  BrushManifest(
    id: 'spot_heal',
    titleKey: 'spotHealTitle',
    icon: Icons.auto_fix_normal,
    shaderAsset: 'assets/shaders/brushes/spot_heal.frag',
    hasMarks: _hasSpotHealMarks,
    layerFactory: _makeSpotHealLayer,
    hashMarks: _hashSpotHealMarks,
    tool: DevelopTool.spotHeal,
    overlayFactory: _makeSpotHealOverlay,
    marksFromJson: (list) => list.map((j) => SpotHealMark.fromJson(j)).toList(),
    deactivate: (ref) =>
        ref.read(spotHealStateProvider.notifier).setMode(SpotHealMode.inactive),
    sectionFactory: (p, oc) => SpotHealSection(params: p, onChanged: oc),
  ),
  // --- 加深减淡 ---
  BrushManifest(
    id: 'dodge_burn',
    titleKey: 'dodgeBurnTitle',
    icon: Icons.tonality,
    shaderAsset: 'assets/shaders/brushes/dodge_burn.frag',
    hasMarks: _hasDodgeBurnMarks,
    layerFactory: _makeDodgeBurnLayer,
    hashMarks: _hashDodgeBurnMarks,
    tool: DevelopTool.dodgeBurn,
    overlayFactory: _makeDodgeBurnOverlay,
    marksFromJson: (list) =>
        list.map((j) => DodgeBurnMark.fromJson(j)).toList(),
    deactivate: (ref) => ref
        .read(dodgeBurnStateProvider.notifier)
        .setBrushMode(DodgeBurnBrushMode.inactive),
    sectionFactory: (p, oc) => DodgeBurnSection(params: p, onChanged: oc),
  ),
  // --- 海绵工具 ---
  BrushManifest(
    id: 'sponge',
    titleKey: 'spongeTitle',
    icon: Icons.water_drop,
    shaderAsset: 'assets/shaders/brushes/sponge.frag',
    hasMarks: _hasSpongeMarks,
    layerFactory: _makeSpongeLayer,
    hashMarks: _hashSpongeMarks,
    tool: DevelopTool.sponge,
    overlayFactory: _makeSpongeOverlay,
    marksFromJson: (list) => list.map((j) => SpongeMark.fromJson(j)).toList(),
    deactivate: (ref) => ref
        .read(spongeStateProvider.notifier)
        .setBrushMode(SpongeBrushMode.inactive),
    sectionFactory: (p, oc) => SpongeSection(params: p, onChanged: oc),
  ),
  // --- 历史记录画笔 ---
  BrushManifest(
    id: 'history_brush',
    titleKey: 'historyBrushTitle',
    icon: Icons.history,
    shaderAsset: 'assets/shaders/brushes/history_brush.frag',
    hasMarks: _hasHistoryMarks,
    layerFactory: _makeHistoryBrushLayer,
    hashMarks: _hashHistoryMarks,
    tool: DevelopTool.historyBrush,
    overlayFactory: _makeHistoryBrushOverlay,
    marksFromJson: (list) => list.map((j) => HistoryMark.fromJson(j)).toList(),
    deactivate: (ref) => ref
        .read(historyBrushStateProvider.notifier)
        .setMode(HistoryBrushMode.inactive),
    sectionFactory: (p, oc) => HistoryBrushSection(params: p, onChanged: oc),
  ),
];

List<StampMark> _marks(AdjustmentParams p, String id) =>
    p.brushMarks[id] ?? const [];

// ── hasMarks ──

bool _hasSpots(AdjustmentParams p) => _marks(p, 'spot_removal').isNotEmpty;
bool _hasHealingMarks(AdjustmentParams p) => _marks(p, 'healing').isNotEmpty;
bool _hasSpotHealMarks(AdjustmentParams p) => _marks(p, 'spot_heal').isNotEmpty;
bool _hasDodgeBurnMarks(AdjustmentParams p) =>
    _marks(p, 'dodge_burn').isNotEmpty;
bool _hasSpongeMarks(AdjustmentParams p) => _marks(p, 'sponge').isNotEmpty;
bool _hasHistoryMarks(AdjustmentParams p) =>
    _marks(p, 'history_brush').isNotEmpty;

// ── hashMarks ──

int _hashSpots(AdjustmentParams p) =>
    Object.hashAll(_marks(p, 'spot_removal').map((m) => m.hashCode));
int _hashHealingMarks(AdjustmentParams p) =>
    Object.hashAll(_marks(p, 'healing').map((m) => m.hashCode));
int _hashSpotHealMarks(AdjustmentParams p) =>
    Object.hashAll(_marks(p, 'spot_heal').map((m) => m.hashCode));
int _hashDodgeBurnMarks(AdjustmentParams p) =>
    Object.hashAll(_marks(p, 'dodge_burn').map((m) => m.hashCode));
int _hashSpongeMarks(AdjustmentParams p) =>
    Object.hashAll(_marks(p, 'sponge').map((m) => m.hashCode));
int _hashHistoryMarks(AdjustmentParams p) =>
    Object.hashAll(_marks(p, 'history_brush').map((m) => m.hashCode));

// ── layerFactory ──

BrushLayerProvider _makeSpotRemovalLayer(ui.FragmentProgram p) =>
    SpotRemovalLayerProvider(program: p);
BrushLayerProvider _makeHealingLayer(ui.FragmentProgram p) =>
    HealingLayerProvider(program: p);
BrushLayerProvider _makeSpotHealLayer(ui.FragmentProgram p) =>
    SpotHealLayerProvider(program: p);
BrushLayerProvider _makeDodgeBurnLayer(ui.FragmentProgram p) =>
    DodgeBurnLayerProvider(program: p);
BrushLayerProvider _makeSpongeLayer(ui.FragmentProgram p) =>
    SpongeLayerProvider(program: p);
BrushLayerProvider _makeHistoryBrushLayer(ui.FragmentProgram p) =>
    HistoryBrushLayerProvider(program: p);

// ── overlayFactory ──

Widget? _makeSpotRemovalOverlay(OverlayFactoryParams p) {
  final st = p.ref.watch(spotRemoveStateProvider);
  final hasPending = hasPendingStampPreview(p.ref, 'spot_removal');
  if (st.mode != SpotRemoveMode.active && !hasPending) return null;
  return SpotRemoveOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
  );
}

Widget? _makeHealingOverlay(OverlayFactoryParams p) {
  final st = p.ref.watch(healingStateProvider);
  if (st.mode != HealingMode.active &&
      !hasPendingStampPreview(p.ref, 'healing')) {
    return null;
  }
  return HealingOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
    interactive: st.mode == HealingMode.active,
  );
}

Widget? _makeSpotHealOverlay(OverlayFactoryParams p) {
  final st = p.ref.watch(spotHealStateProvider);
  if (st.mode != SpotHealMode.active) return null;
  return SpotHealOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
  );
}

Widget? _makeDodgeBurnOverlay(OverlayFactoryParams p) {
  final st = p.ref.watch(dodgeBurnStateProvider);
  if (st.brushMode != DodgeBurnBrushMode.active) return null;
  return DodgeBurnOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
  );
}

Widget? _makeSpongeOverlay(OverlayFactoryParams p) {
  final st = p.ref.watch(spongeStateProvider);
  if (st.brushMode != SpongeBrushMode.active) return null;
  return SpongeOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
  );
}

Widget? _makeHistoryBrushOverlay(OverlayFactoryParams p) {
  if (p.ref.watch(historyBrushStateProvider).mode != HistoryBrushMode.active) {
    return null;
  }
  return HistoryBrushOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
  );
}

/// 按 [DevelopTool] 枚举值查找 [BrushManifest]
BrushManifest? manifestForTool(DevelopTool tool) {
  for (final m in brushManifests) {
    if (m.tool == tool) return m;
  }
  return null;
}

/// 按 brush ID 字符串查找 [BrushManifest]
BrushManifest? manifestForId(String id) {
  for (final m in brushManifests) {
    if (m.id == id) return m;
  }
  return null;
}
