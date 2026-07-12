import 'stamp/stamp_mark.dart';

/// 图章 marks 哈希，用于缓存键和 committed-preview 匹配
int hashSpots(List<StampMark> marks) =>
    Object.hashAll(marks.map((s) => s.hashCode));

/// 修复画笔 marks 哈希，用于缓存键和 committed-preview 匹配
int hashHealingMarks(List<StampMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));

/// 污点修复 marks 哈希，用于缓存键匹配
/// 排除 createdAt：timestamp 不影响像素输出，允许缓存跨时间排序复用
int hashSpotHealMarks(List<StampMark> marks) => Object.hashAll(
  marks.map((m) => Object.hash(m.target, m.radius, m.hardness)),
);

/// 加深减淡 marks 哈希，用于缓存键匹配
/// 每个 mark 的 hashCode 已包含其 per-mark 渲染参数（mode/range/exposure）
int hashDodgeBurnMarks(List<StampMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));

/// 海绵 marks 哈希，用于缓存键匹配
/// 每个 mark 的 hashCode 已包含其 per-mark 渲染参数（mode/flow）
int hashSpongeMarks(List<StampMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));

/// 历史记录画笔 marks 哈希，用于缓存键匹配
int hashHistoryMarks(List<StampMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
