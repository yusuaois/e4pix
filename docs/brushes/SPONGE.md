# 海绵工具 (Sponge) 技术文档

## 1. 功能概述

基于 GPU shader 的 Photoshop 风格海绵工具，通过 HSL 饱和度调整局部增加或降低色彩饱和度，支持 saturate/desaturate 双模式。

- **操作方式**：直接涂抹（无需 Alt+取样），原地修改像素饱和度
- **交互模式**：无极画笔，自由路径，连续路径预览
- **核心效果**：saturate 增加饱和度（朝纯色方向），desaturate 降低饱和度（朝灰度方向），通过 flow 参数控制单笔强度
- **Per-mark 参数冻结**：落笔时 mode/flow 存入 mark，切换不影响旧笔画

与其他画笔的对比：

| | 加深减淡 | 海绵 | 污点修复 |
|---|---|---|---|
| 效果 | 亮度 ± | **饱和度 ±** | 像素填充 |
| 算法 | Screen/Multiply | **HSL sat adj** | 射线+IDW |
| 色调范围 | Shadows/Midtones/Highlights | **全部色相** | — |
| Per-mark | mode+range+exposure | **mode+flow** | — |

## 2. 架构

海绵工具按画笔插槽式架构开发，接入 Compose 图层系统：

```
┌──────────────────────────────────────────────────┐
│ Overlay: sponge_overlay.dart                     │
│   ├── 无极画笔交互（PathBrushTracker）             │
│   ├── 连续路径预览（StrokeCap.round 粗线）         │
│   └── 光标：saturate=橙(#FF9900) desaturate=灰    │
├──────────────────────────────────────────────────┤
│ State: sponge_state.dart                         │
│   ├── SpongeBrushMode { inactive, active }        │
│   ├── SpongeState (mode, flow, brushRadius,       │
│   │   brushHardness)                              │
│   └── SpongeNotifier → params.brushMarks          │
├──────────────────────────────────────────────────┤
│ Model: sponge_model.dart                         │
│   ├── SpongeMode { saturate, desaturate }         │
│   └── SpongeMark { target, radius, hardness,     │
│       mode, flow, createdAt }                     │
├──────────────────────────────────────────────────┤
│ Layer: sponge_layer.dart (Compose)                │
│   ├── marks → 按(mode,flow)分组                   │
│   ├── 每组光栅化 mask → 单 shader pass            │
│   └── 链式叠加各组输出                             │
├──────────────────────────────────────────────────┤
│ Shader: sponge.frag                               │
│   ├── 输入: uImage + uMask + uSize + uMode        │
│   │        + uFlow + uHardness                    │
│   ├── RGB→HSL→调整 S→HSL→RGB                      │
│   └── mask 羽化边缘混合                            │
└──────────────────────────────────────────────────┘
```

### 2.1 管线位置

```
源图 → 降噪 → 镜头校正 → Develop → Mask
     → Compose(图章 → 修复画笔 → 污点修复 → 加深减淡 → 海绵)
     → 透视 → 裁剪 → 锐化 → 输出
```

### 2.2 文件清单

| 文件 | 职责 |
|------|------|
| `lib/brushes/sponge/sponge_model.dart` | SpongeMark + SpongeMode |
| `lib/brushes/sponge/sponge_state.dart` | SpongeNotifier + SpongeState |
| `lib/brushes/sponge/sponge_overlay.dart` | 无极画笔交互 + 连续路径 Canvas 预览 + 颜色光标 |
| `lib/brushes/sponge/sponge_section.dart` | UI 面板（激活/模式/流量/半径/硬度/清除） |
| `lib/brushes/sponge/sponge_layer.dart` | Compose 图层：分组 mask 光栅化 + 链式 shader |
| `assets/shaders/brushes/sponge.frag` | Shader 源码（编译：`flutter build bundle`） |

## 3. Shader 算法

### 3.1 算法流程

```
对 mask 内每个像素:
  1. 读取 src RGB
  2. RGB → HSL:
     - L = (max + min) / 2
     - S = (max - min) / (1 - |2L - 1|)  (HSL 饱和度)
     - H = hue from (max, mid, min)
  3. 调整 S:
     - Saturate:   S' = S + (1 - S) × flow × mask   (向 1 靠拢)
     - Desaturate: S' = S × (1 - flow × mask)         (向 0 靠拢)
  4. HSL → RGB（H 和 L 不变）
  5. 羽化混合: output = mix(src, result, maskEdge)
```

### 3.2 为什么用 HSL 而非 HSV

- **HSL** S=0 为灰色，S=1 为纯色，saturate 效果均匀
- **HSV** S=1 时 L 值极端的像素（纯黑/纯白）饱和度定义不稳定，desaturate 后偏色

### 3.3 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| flow | 0..1，默认 0.5 | 单笔饱和度变化强度 |
| saturate 公式 | S' = S + (1-S) × flow | 越饱和变化越小，避免过饱和 |
| desaturate 公式 | S' = S × (1-flow) | 线性下降，50% flow → 半饱和 |
| 羽化 | smoothstep(硬度) | 与 mask 边缘配合 |

### 3.4 为什么是 mask 而非离散圆

同加深减淡——离散圆重叠处效果叠加（saturate×2），mask 方案单 pass 保证饱和度调整线性可预测。

## 4. 渲染架构

### 4.1 Per-mark 参数冻结

每个 `SpongeMark` 在落笔时冻结当前工具参数：

```dart
// sponge_state.dart
void addMarkAt(Offset target, double radiusNorm, double hardness) {
  final s = state;
  final mark = SpongeMark(
    target: target, radius: radiusNorm, hardness: hardness,
    mode: s.mode, flow: s.flow,       // ← 冻结
    createdAt: DateTime.now(),
  );
  _addMarkRaw(mark);
}
```

笔画路径通过 `addStrokesBatch` 批量提交——所有 marks 共享同一 `DateTime.now()`，保持 time-sorted rendering 中笔画粒度正确。

### 4.2 分组渲染

当存在多组不同参数 marks 时，按 `(mode, flow)` 分组：

| 场景 | shader pass 数 |
|------|---------------|
| 同种参数（如全部 saturate 0.5） | 1 |
| saturate + desaturate 混合 | 2 |
| N 种 flow 值混合 | N |

### 4.3 缓存策略

- **Level 1（marks hash cache）**：key = `(developKey, hash of all marks)`。marks 的 hashCode 包含 mode/flow，切换工具参数不改变 marks → 缓存命中
- **无 Level 2 缓存**：所有 marks 光栅化到一张 mask，非逐 mark 渲染

## 5. 交互设计

### 5.1 无极画笔

- `PathBrushTracker(spacing: 0.005)` 均匀采样路径点
- 笔刷预览：连续粗线路径（`PaintingStyle.stroke` + `StrokeCap.round`），线宽 = `radius × 2 × displayWidth`
- 光标：颜色圆环（`strokeWidth: 1.5`），saturate=橙色，desaturate=灰色
- 松手后一次批量提交所有 marks

### 5.2 坐标系统

- **SpongeMark.target**：归一化 [0..1] 全图坐标
- **radius**：归一化值，UI 显示值 = radius × 1000，默认 20 → 0.02
- **hardness**：0..1，默认 1.0（硬边）
- **flow**：0..1，默认 0.5（50%），控制单笔饱和度变化强度
- **mode**：saturate（增饱和）/ desaturate（降饱和）

## 6. Compose 图层注册

海绵通过 `SpongeLayerProvider` 接入 Compose 系统——与其他画笔同样模式，所有通路（预览/导出/水印/分割对比）自动生效。

时间排序渲染：多画笔共存时，按 `StampMark.createdAt` 全局排序后链式渲染，跨画笔交替绘制自动按实际绘制顺序叠加。

## 7. 与 Photoshop 的一致性

| 特性 | Photoshop | e4pix |
|------|-----------|-------|
| 双模式 | Saturate / Desaturate | ✅ 同款 |
| HSL 空间 | ✅ | ✅ 同款 |
| Flow 控制 | 0-100% | ✅ 0..1（50% 默认） |
| Per-stroke 参数 | 每次落笔时的工具设置 | ✅ 落笔时冻结入 mark |
| 多参数混合 | ✅ 支持 | ✅ 分组渲染 |
| Vibrance 选项 | PS 有 Vibrance 模式 | ❌ 未实现（可后续添加） |

## 8. 已知局限

- **无 Vibrance 模式**：PS 的海绵工具有 "Vibrance" 复选框（保护肤色不饱和/不降饱和），e4pix 暂未实现
- **分组渲染开销**：N 种不同 (mode, flow) 组合 → N 次 shader pass。实际使用中通常 1-2 组
- **HSL 极端值**：纯黑（L=0）和纯白（L=1）像素的 S 无定义，saturate/desaturate 对它们无效果——符合 PS 行为
- **flow 叠加**：多次短笔重叠处效果累积，单次长笔拖拽 mask 为 1 处效果恒稳——mask 方案保证重叠不翻倍
