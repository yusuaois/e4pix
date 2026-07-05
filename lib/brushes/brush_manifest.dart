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
  /// Unique id matching [BrushLayerProvider.id].
  final String id;

  /// Translation key for the tool's display name (e.g. 'spotRemoveTitle').
  final String titleKey;

  /// Icon for the tool rail / tab.
  final IconData icon;

  /// Asset path for this brush's compiled fragment shader.
  final String shaderAsset;

  /// Whether this brush has active marks in the given params.
  final bool Function(AdjustmentParams) hasMarks;

  /// Factory: creates a [BrushLayerProvider] from a compiled program.
  final BrushLayerProvider Function(ui.FragmentProgram program) layerFactory;

  /// Hash of all marks for cache-key and committed-preview matching.
  final int Function(AdjustmentParams params) hashMarks;

  /// The [DevelopTool] enum value associated with this brush.
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

/// Single source of truth for all brush tools.
///
/// Registration order determines Compose layer order (first = bottom layer)
/// and tab/rail order in both panels.
const brushManifests = <BrushManifest>[
  // --- Clone Stamp (图章) ---
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
  // --- Healing Brush (修复画笔) ---
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
  // --- Spot Heal (污点修复) ---
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
  // --- Dodge & Burn (加深减淡) ---
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

// Private helpers

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

// Public helpers

/// Lookup a [BrushManifest] by its [DevelopTool] enum value.
BrushManifest? manifestForTool(DevelopTool tool) {
  for (final m in brushManifests) {
    if (m.tool == tool) return m;
  }
  return null;
}
