import 'adjustment_params.dart';

/// 可选择性同步的调整项分组
enum SyncItem {
  whiteBalance, // temperature, tint
  tone,         // exposure, contrast, highlights, shadows, whites, blacks
  presence,     // saturation, vibrance
  hsl,
  curves,
  lut,          // lutIntensity, lutIntensityB
  locals,
  crop,
}

extension SyncItemLabel on SyncItem {
  String get labelKey => switch (this) {
        SyncItem.whiteBalance => 'syncWhiteBalance',
        SyncItem.tone => 'syncTone',
        SyncItem.presence => 'syncPresence',
        SyncItem.hsl => 'syncHsl',
        SyncItem.curves => 'syncCurves',
        SyncItem.lut => 'syncLut',
        SyncItem.locals => 'syncLocals',
        SyncItem.crop => 'syncCrop',
      };
}

/// 默认勾选：调色风格类（保留各自曝光/白平衡/构图）
const kDefaultSyncItems = {
  SyncItem.presence,
  SyncItem.hsl,
  SyncItem.curves,
};

/// 把 src 的选中项合并进 target，未选中项保留 target 原值
AdjustmentParams mergeParams(
  AdjustmentParams target,
  AdjustmentParams src,
  Set<SyncItem> items,
) {
  return target.copyWith(
    temperature: items.contains(SyncItem.whiteBalance) ? src.temperature : null,
    tint: items.contains(SyncItem.whiteBalance) ? src.tint : null,
    exposure: items.contains(SyncItem.tone) ? src.exposure : null,
    contrast: items.contains(SyncItem.tone) ? src.contrast : null,
    highlights: items.contains(SyncItem.tone) ? src.highlights : null,
    shadows: items.contains(SyncItem.tone) ? src.shadows : null,
    whites: items.contains(SyncItem.tone) ? src.whites : null,
    blacks: items.contains(SyncItem.tone) ? src.blacks : null,
    saturation: items.contains(SyncItem.presence) ? src.saturation : null,
    vibrance: items.contains(SyncItem.presence) ? src.vibrance : null,
    hsl: items.contains(SyncItem.hsl) ? src.hsl : null,
    curves: items.contains(SyncItem.curves) ? src.curves : null,
    lutIntensity: items.contains(SyncItem.lut) ? src.lutIntensity : null,
    lutIntensityB: items.contains(SyncItem.lut) ? src.lutIntensityB : null,
    locals: items.contains(SyncItem.locals) ? src.locals : null,
    crop: items.contains(SyncItem.crop) ? src.crop : null,
  );
}