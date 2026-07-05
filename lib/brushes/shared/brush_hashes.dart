import '../clone_stamp/clone_stamp_model.dart';
import '../healing/healing_model.dart';
import '../spot_heal/spot_heal_model.dart';
import '../dodge_burn/dodge_burn_model.dart';

/// 图章 marks 哈希，用于缓存键和 committed-preview 匹配
int hashSpots(List<SpotMark> spots) =>
    Object.hashAll(spots.map((s) => s.hashCode));

/// 修复画笔 marks 哈希，用于缓存键和 committed-preview 匹配
int hashHealingMarks(List<HealingMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));

/// 污点修复 marks 哈希，用于缓存键匹配
int hashSpotHealMarks(List<SpotHealMark> marks) => Object.hashAll(
  marks.map((m) => Object.hash(m.target, m.radius, m.hardness)),
);

/// 加深减淡 marks 哈希，用于缓存键匹配
/// 每个 mark 的 hashCode 已包含其 per-mark 渲染参数（mode/range/exposure）
int hashDodgeBurnMarks(List<DodgeBurnMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
