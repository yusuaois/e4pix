import '../core/constants/math_constants.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/local_adjustment.dart';

/// Pure functions that answer "is this pass needed?" from [AdjustmentParams].
///
/// Centralised so the pipeline, preview widgets, watermark preview, and exporter
/// all derive pass-activity from a single source of truth instead of duplicating
/// the same threshold / isNeutral checks.

/// Whether the denoise pass is required.
bool needsDenoisePass(AdjustmentParams p) =>
    p.denoiseLuma > kParamEpsilon || p.denoiseColor > kParamEpsilon;

/// Whether the sharpen pass is required.
bool needsSharpenPass(AdjustmentParams p) =>
    p.sharpenAmount > kParamEpsilon;

/// Whether the perspective / keystone pass is required.
bool needsPerspectivePass(AdjustmentParams p) =>
    !p.perspective.isIdentity;

/// Whether the lens-correction pass is required
/// (distortion, CA, or vignetting).
bool needsLensCorrectionPass(AdjustmentParams p) =>
    p.lensCorrection.isDistortionActive ||
    p.lensCorrection.isCaActive ||
    p.lensCorrection.isVignettingActive;

/// Enabled local adjustments whose params are non-neutral.
List<LocalAdjustment> activeLocals(AdjustmentParams p) =>
    p.locals.where((l) => l.enabled && !l.params.isNeutral).toList();

/// Whether at least one enabled local adjustment has a non-neutral mask.
bool hasActiveLocals(AdjustmentParams p) => activeLocals(p).isNotEmpty;

/// Whether any spot-removal marks exist.
bool hasSpots(AdjustmentParams p) => p.spots.isNotEmpty;

/// Whether any healing-brush marks exist.
bool hasHealingMarks(AdjustmentParams p) => p.healingMarks.isNotEmpty;

/// Whether the full pipeline (beyond a simple develop pass) is required.
bool needsFullPipeline(AdjustmentParams p) =>
    hasActiveLocals(p) ||
    needsSharpenPass(p) ||
    needsDenoisePass(p) ||
    needsLensCorrectionPass(p) ||
    needsPerspectivePass(p) ||
    hasSpots(p) ||
    hasHealingMarks(p);
