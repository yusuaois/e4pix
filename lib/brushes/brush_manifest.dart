import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../core/models/adjustment_params.dart';
import '../render/brush_layer_provider.dart';
import '../state/tools/develop_tool_state.dart';

import 'clone_stamp/clone_stamp_layer.dart';
import 'healing/healing_layer.dart';
import 'spot_heal/spot_heal_layer.dart';
import 'dodge_burn/dodge_burn_layer.dart';
import 'shared/brush_hashes.dart';

/// Self-describing metadata for a brush tool.
///
/// Integration points (shader loading, pass config, layer registry,
/// warmup, UI panels) iterate over [brushManifests] instead of having
/// per-brush code.
class BrushManifest {
  /// 唯一 id，对应 [BrushLayerProvider.id]
  final String id;

  /// 工具显示名称的翻译 key（如 'spotRemoveTitle'）
  final String titleKey;

  /// 工具栏/标签页图标
  final IconData icon;

  /// 笔刷已编译 fragment shader 的资源路径
  final String shaderAsset;

  /// 笔刷在给定 params 中是否有活跃 marks
  final bool Function(AdjustmentParams) hasMarks;

  /// 从已编译 program 创建 [BrushLayerProvider] 的工厂函数
  final BrushLayerProvider Function(ui.FragmentProgram program) layerFactory;

  /// 所有 marks 的哈希，用于缓存键和已提交预览匹配
  final int Function(AdjustmentParams params) hashMarks;

  /// 关联此笔刷的 [DevelopTool] 枚举值
  final DevelopTool tool;

  const BrushManifest({
    required this.id,
    required this.titleKey,
    required this.icon,
    required this.shaderAsset,
    required this.hasMarks,
    required this.layerFactory,
    required this.hashMarks,
    required this.tool,
  });
}

/// 所有笔刷工具的唯一数据源
///
/// 注册顺序决定 Compose 层级（首个=底层）和面板 tab/rail 顺序
const brushManifests = <BrushManifest>[
  // --- 图章 ---
  BrushManifest(
    id: 'spot_removal',
    titleKey: 'spotRemoveTitle',
    icon: Icons.healing,
    shaderAsset: 'assets/shaders/spot_remove.shader',
    hasMarks: _hasSpots,
    layerFactory: _makeSpotRemovalLayer,
    hashMarks: _hashSpots,
    tool: DevelopTool.spotRemove,
  ),
  // --- 修复画笔 ---
  BrushManifest(
    id: 'healing',
    titleKey: 'healingTitle',
    icon: Icons.auto_fix_high,
    shaderAsset: 'assets/shaders/healing.shader',
    hasMarks: _hasHealingMarks,
    layerFactory: _makeHealingLayer,
    hashMarks: _hashHealingMarks,
    tool: DevelopTool.healing,
  ),
  // --- 污点修复 ---
  BrushManifest(
    id: 'spot_heal',
    titleKey: 'spotHealTitle',
    icon: Icons.auto_fix_normal,
    shaderAsset: 'assets/shaders/spot_heal.shader',
    hasMarks: _hasSpotHealMarks,
    layerFactory: _makeSpotHealLayer,
    hashMarks: _hashSpotHealMarks,
    tool: DevelopTool.spotHeal,
  ),
  // --- 加深减淡 ---
  BrushManifest(
    id: 'dodge_burn',
    titleKey: 'dodgeBurnTitle',
    icon: Icons.tonality,
    shaderAsset: 'assets/shaders/dodge_burn.shader',
    hasMarks: _hasDodgeBurnMarks,
    layerFactory: _makeDodgeBurnLayer,
    hashMarks: _hashDodgeBurnMarks,
    tool: DevelopTool.dodgeBurn,
  ),
];

// 私有辅助函数

bool _hasSpots(AdjustmentParams p) => p.spots.isNotEmpty;
bool _hasHealingMarks(AdjustmentParams p) => p.healingMarks.isNotEmpty;
bool _hasSpotHealMarks(AdjustmentParams p) => p.spotHealMarks.isNotEmpty;
bool _hasDodgeBurnMarks(AdjustmentParams p) => p.dodgeBurnMarks.isNotEmpty;

int _hashSpots(AdjustmentParams p) => hashSpots(p.spots);
int _hashHealingMarks(AdjustmentParams p) => hashHealingMarks(p.healingMarks);
int _hashSpotHealMarks(AdjustmentParams p) =>
    hashSpotHealMarks(p.spotHealMarks);
int _hashDodgeBurnMarks(AdjustmentParams p) =>
    hashDodgeBurnMarks(p.dodgeBurnMarks);

BrushLayerProvider _makeSpotRemovalLayer(ui.FragmentProgram p) =>
    SpotRemovalLayerProvider(program: p);
BrushLayerProvider _makeHealingLayer(ui.FragmentProgram p) =>
    HealingLayerProvider(program: p);
BrushLayerProvider _makeSpotHealLayer(ui.FragmentProgram p) =>
    SpotHealLayerProvider(program: p);
BrushLayerProvider _makeDodgeBurnLayer(ui.FragmentProgram p) =>
    DodgeBurnLayerProvider(program: p);

/// 按 [order] 排序 manifest 列表（ID 不在 order 中的追加到末尾）
List<BrushManifest> orderedManifests(List<String> order) {
  final sorted = brushManifests.toList()
    ..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
  return sorted;
}

// 公开辅助函数

/// 按 [DevelopTool] 枚举值查找 [BrushManifest]
BrushManifest? manifestForTool(DevelopTool tool) {
  for (final m in brushManifests) {
    if (m.tool == tool) return m;
  }
  return null;
}
