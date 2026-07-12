# 加深减淡 (Dodge & Burn) 技术文档

## 1. 功能概述

基于 GPU shader 的 Photoshop 风格加深减淡工具，通过 Screen/Multiply 混合模式局部提亮或压暗图像，支持三色调范围（Shadows/Midtones/Highlights）选择。

- **操作方式**：直接涂抹（无需 Alt+取样），原地修改像素亮度
- **交互模式**：无极画笔，自由路径，连续路径预览
- **核心效果**：Screen blend（减淡）+ Multiply blend（加深），通过亮度遮罩限制在选定色调范围
- **Per-mark 参数冻结**：落笔时 mode/range/exposure 存入 mark，切换不影响旧笔画

与四个画笔的对比：

| | 图章 | 修复画笔 | 污点修复 | 加深减淡 |
|---|---|---|---|---|
| 源点 | 手动取样 | 手动取样 | 自动边界 | **无（原地）** |
| 算法 | 直接克隆 | 边界色校正 | 射线+IDW | **Screen/Multiply** |
| 选区 | 离散圆 | 离散圆 | 无极涂抹 | **无极涂抹** |
| 色调范围 | — | — | — | **Shadows/Midtones/Highlights** |

## 2. 架构

加深减淡按画笔插槽式架构开发，接入 Compose 图层系统：

```
┌──────────────────────────────────────────────────┐
│ Overlay: dodge_burn_overlay.dart                 │
│   ├── 无极画笔交互（PathBrushTracker）             │
│   ├── 连续路径预览（StrokeCap.round 粗线）         │
│   └── 光标：减淡=金(#FFCC00) 加深=蓝(#0088FF)     │
├──────────────────────────────────────────────────┤
│ State: dodge_burn_state.dart                     │
│   ├── DodgeBurnBrushMode { inactive, active }     │
│   ├── DodgeBurnState (mode, range, exposure,      │
│   │   brushRadius, brushHardness)                 │
│   └── DodgeBurnNotifier → params.dodgeBurnMarks   │
├──────────────────────────────────────────────────┤
│ Model: dodge_burn_model.dart                     │
│   ├── DodgeBurnMode { dodge, burn }              │
│   ├── DodgeBurnRange { shadows, midtones,        │
│   │   highlights }                               │
│   └── DodgeBurnMark { target, radius, hardness,  │
│       mode, range, exposure }                    │
├──────────────────────────────────────────────────┤
│ Layer: dodge_burn_layer.dart (Compose)            │
│   ├── marks → 按(mode,range,exposure)分组        │
│   ├── 每组光栅化 mask → 单 shader pass            │
│   └── 链式叠加各组输出                             │
├──────────────────────────────────────────────────┤
│ Shader: dodge_burn.frag                  │
│   ├── 输入: uImage + uMask + uSize + uMode       │
│   │        + uExposure + uRange                  │
│   ├── 亮度遮罩（range mask）限制色调范围            │
│   └── Screen (dodge) / Multiply (burn) 混合       │
└──────────────────────────────────────────────────┘
```

### 2.1 管线位置

```
源图 → 降噪 → 镜头校正 → Develop → Mask
     → Compose(图章 → 修复画笔 → 污点修复 → 加深减淡)
     → 透视 → 裁剪 → 锐化 → 输出
```

### 2.2 文件清单

| 文件 | 职责 |
|------|------|
| `lib/brushes/dodge_burn/dodge_burn_model.dart` | DodgeBurnMark + DodgeBurnMode + DodgeBurnRange |
| `lib/brushes/dodge_burn/dodge_burn_state.dart` | DodgeBurnNotifier + DodgeBurnState |
| `lib/brushes/dodge_burn/dodge_burn_overlay.dart` | 无极画笔交互 + 连续路径 Canvas 预览 + 颜色光标 |
| `lib/brushes/dodge_burn/dodge_burn_section.dart` | UI 面板（激活/模式/范围/曝光/半径/硬度/清除） |
| `lib/brushes/dodge_burn/dodge_burn_layer.dart` | Compose 图层：分组 mask 光栅化 + 链式 shader |
| `lib/brushes/dodge_burn/dodge_burn_cache.dart` | hash 函数（含 per-mark 参数） |
| `assets/shaders/brushes/dodge_burn.frag` | Shader 源码（编译：`flutter build bundle` → `build/flutter_assets/assets/shaders/brushes/dodge_burn.frag` → 重命名为 `.shader`） |

## 3. Shader 算法

### 3.1 算法流程

```
对 mask 内每个像素:
  1. 计算亮度: lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722)) — BT.709
  2. 色调范围遮罩 (rangeMask):
     - Shadows:  1.0 - smoothstep(0.0, 0.75, lum)    峰值在 lum=0
     - Midtones: smoothstep(0,0.5,lum) × (1-smoothstep(0.5,1,lum))  钟形，峰值在 lum=0.5
     - Highlights: smoothstep(0.25, 1.0, lum)        峰值在 lum=1
  3. 综合强度: s = clamp(mask × exposure × rangeMask × 0.7, 0, 0.95)
  4. 混合:
     - Dodge: result = src + (1 - src) × s   (Screen blend)
     - Burn:  result = src × (1 - s)          (Multiply blend)
  5. clamp(result, 0, 1) 防止浮点精度超范围
```

### 3.2 PS 校准

**0.7 系数来源**：PS 50% 曝光 + 中间调 + 中性灰 (lum=0.5) 单笔提亮约 17%：
```
s = 1.0(mask) × 0.5(exposure) × 1.0(rangeMask) × 0.7 = 0.35
Dodge: 0.5 + 0.5 × 0.35 = 0.675  ✓ (+17%)
Burn:  0.5 × (1 - 0.35) = 0.325    ✓ (-17%)
```

### 3.3 为什么用 Screen/Multiply 而非 Color Dodge/Burn

Color Dodge (`a/(1-s)`) 在 s=0.5 时即爆炸：
```
0.5 / (1 - 0.5) = 1.0   → 纯白！一笔打满
```

Screen (`a + (1-a)×s`) 线性安全，同样参数：
```
0.5 + 0.5 × 0.5 × 0.7 = 0.675  → 温和提亮
```

### 3.4 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 亮度系数 | BT.709 (0.2126, 0.7152, 0.0722) | ITU-R 标准感知亮度 |
| 校准系数 | 0.7 | PS 等效强度映射 |
| s clamp | 0～0.95 | 防止单笔纯白/纯黑 |
| 范围遮罩过渡 | smoothstep 宽过渡 | 避免色调范围边界突变 |
| uniform 数量 | 6 (size×2 + mode + exposure + range + **padding**) | 对齐到 6 避免 GPU 问题 |

### 3.5 为什么是 mask 而非离散圆

- 离散圆叠加方案：涂抹路径 → 密集小圆 → shader 逐圆处理。Dodge/Burn 的效果是叠加性的——两个半透明圆重叠处效果加倍，与 PS 不一致
- Mask 方案：涂抹路径 → 光栅化为一整张羽化 mask 纹理 → shader 单 pass → mask 值在重叠处自然 clamp 到 1，效果线性可预测

## 4. 渲染架构

### 4.1 Per-mark 参数冻结

每个 `DodgeBurnMark` 在落笔时冻结当前工具参数：

```dart
// dodge_burn_state.dart
void addMarkAt(Offset target, double radiusNorm, double hardness) {
  final s = state;  // 冻结当前 tool state
  final mark = DodgeBurnMark(
    target: target, radius: radiusNorm, hardness: hardness,
    mode: s.mode, range: s.range, exposure: s.exposure,  // ← 冻结
  );
  _addMarkRaw(mark);
}
```

切换 mode/range/exposure → 只影响后续新笔画 → 旧笔画参数不变 → 缓存命中 → 不重渲染。

### 4.2 分组渲染

当存在多组不同参数 marks 时，按 `(mode, range, exposure)` 分组：

```dart
// dodge_burn_layer.dart
final groups = <int, List<DodgeBurnMark>>{};
for (final m in marks) {
  groups.putIfAbsent(_groupKey(m), () => []).add(m);
}

// 每组一次 shader pass，链式叠加
ui.Image current = base;
for (final group in groups.values) {
  final mask = await rasterizeBrushMask(group);
  final result = await runSingleShaderPass(..., samplers: [current, mask]);
  if (current != base) current.dispose();
  current = result;
}
```

| 场景 | shader pass 数 |
|------|---------------|
| 同种参数（如全部减淡+阴影） | 1 |
| 2 种参数混合 | 2 |
| N 种参数混合 | N |

### 4.3 缓存策略

- **Level 1（marks hash cache）**：key = `(developKey, hash of all marks)`。marks 的 hashCode 包含 mode/range/exposure，切换工具参数不改变 marks → 缓存命中 → 0 GPU pass
- **无 Level 2 缓存**：spot_heal 和 dodge_burn 均不使用增量滚动缓存（所有 marks 光栅化到一张 mask，非逐 mark 渲染）

## 5. 交互设计

### 5.1 无极画笔

- `PathBrushTracker(spacing: 0.005)` 均匀采样路径点
- 笔刷预览：连续粗线路径（`PaintingStyle.stroke` + `StrokeCap.round`），线宽 = `radius × 2 × displayWidth`
- 光标：颜色圆环（`strokeWidth: 1.5`），减淡=金色 `#80FFCC00`，加深=蓝色 `#800088FF`
- 松手后一次批量提交所有 marks

### 5.2 坐标系统

- **DodgeBurnMark.target**：归一化 [0..1] 全图坐标
- **radius**：归一化值，UI 显示值 = radius × 1000（单位 ‰），默认 20
- **hardness**：0..1，默认 1.0（硬边）
- **exposure**：0..1，默认 0.5（50%），控制单笔效果强度
- **mode**：dodge（Screen 提亮）/ burn（Multiply 压暗）
- **range**：shadows / midtones / highlights，限制效果到选定色调范围

## 6. Compose 图层注册

加深减淡通过 `DodgeBurnLayerProvider` 接入 Compose 系统：

```dart
// multi_pass_preview.dart
final dodgeBurnProgram = ref.read(dodgeBurnShaderProgramProvider).value;
if (dodgeBurnProgram != null) {
  _dodgeBurnLayer ??= DodgeBurnLayerProvider(program: dodgeBurnProgram);
  providers.add(_dodgeBurnLayer!);
}
```

与其他三个画笔同样模式——所有通路（预览/导出/水印/分割对比）自动生效。

## 7. 与 Photoshop 的一致性

| 特性 | Photoshop | e4pix |
|------|-----------|-------|
| 混合模式 | Screen / Multiply | ✅ Screen / Multiply |
| 三色调范围 | Shadows/Midtones/Highlights | ✅ 同款 smoothstep 宽过渡 |
| 曝光 50% 中性灰效果 | +17% (dodge) / -17% (burn) | ✅ 0.7 校准系数匹配 |
| Per-stroke 参数 | 每次落笔时的工具设置 | ✅ 落笔时冻结入 mark |
| 多参数混合 | ✅ 支持 | ✅ 分组渲染 |
| Color Dodge/Burn | ❌ 不用于强度调节 | ❌ 已确认不适合并替换 |

## 8. 已知局限

- **分组渲染开销**：N 种不同参数组合 → N 次 shader pass。实际使用中通常 1-2 组
- **缓存命中条件**：marks 的 hashCode 改变才重渲染。如果完全相同的 marks 列表在不同 developKey 下需要新结果，由 Level 1 的双 key 检查保证
- **mask 光栅化上限**：单 mark 半径 clamp 到 0.5，避免超大 mask 纹理消耗 GPU 内存
- **uniform 对齐**：5 个有效 float → 对齐到 6 个避免 GPU 驱动问题。第 6 个 float 声明但未使用
