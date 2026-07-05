import '../brushes/brush_manifest.dart';
import '../core/constants/math_constants.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/local_adjustment.dart';

/// 纯函数：从 [AdjustmentParams] 判断"是否需要某趟"
///
/// 集中管理，管线、预览组件、水印预览、导出器均从此单一来源获取趟激活状态，
/// 避免重复阈值 / isNeutral 检查

/// 是否需要降噪趟
bool needsDenoisePass(AdjustmentParams p) =>
    p.denoiseLuma > kParamEpsilon || p.denoiseColor > kParamEpsilon;

/// 是否需要锐化趟
bool needsSharpenPass(AdjustmentParams p) => p.sharpenAmount > kParamEpsilon;

/// 是否需要透视 / 梯形校正趟
bool needsPerspectivePass(AdjustmentParams p) => !p.perspective.isIdentity;

/// 是否需要镜头校正趟（畸变、色差或暗角）
bool needsLensCorrectionPass(AdjustmentParams p) =>
    p.lensCorrection.isDistortionActive ||
    p.lensCorrection.isCaActive ||
    p.lensCorrection.isVignettingActive;

/// 参数非中性且已启用的局部调整
List<LocalAdjustment> activeLocals(AdjustmentParams p) =>
    p.locals.where((l) => l.enabled && !l.params.isNeutral).toList();

/// 是否至少有一个已启用的局部调整拥有非中性蒙版
bool hasActiveLocals(AdjustmentParams p) => activeLocals(p).isNotEmpty;

/// 是否有已注册画笔包含活跃标记
bool _anyBrushActive(AdjustmentParams p) =>
    brushManifests.any((m) => m.hasMarks(p));

/// 是否需要完整管线（超过简单调色趟）
bool needsFullPipeline(AdjustmentParams p) =>
    hasActiveLocals(p) ||
    needsSharpenPass(p) ||
    needsDenoisePass(p) ||
    needsLensCorrectionPass(p) ||
    needsPerspectivePass(p) ||
    _anyBrushActive(p);

/// 是否需要合成趟（有画笔含活跃标记）
bool needsComposePass(AdjustmentParams p) => _anyBrushActive(p);
