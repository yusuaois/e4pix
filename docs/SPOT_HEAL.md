# 污点修复 (Spot Heal) 技术文档

## 1. 功能概述

基于 GPU shader 的真正污点修复（PS Spot Healing Brush），用户自由涂抹选区，工具自动从选区周围采样像素填充。

- **操作方式**：直接涂抹（无需 Alt+取样）
- **交互模式**：无极画笔，自由路径，与 Detail 笔刷同款连续路径预览
- **核心效果**：沿 16 个方向射线搜索 mask 边界，IDW（反距离加权）采样填充

与图章、修复画笔的区别：

| | 图章 (Clone Stamp) | 修复画笔 (Healing) | 污点修复 (Spot Heal) |
|---|---|---|---|
| 源点 | 手动 Alt+取样 | 手动 Alt+取样 | **自动（边界）** |
| 填充 | 直接克隆 | 边界色校正 | **射线搜索 + IDW** |
| 选区 | 离散圆 | 离散圆 | **无极涂抹 → mask 光栅化** |

## 2. 架构

污点修复按画笔插槽式架构开发，接入 Compose 图层系统：

```
┌──────────────────────────────────────────────────┐
│ Overlay: spot_heal_overlay.dart                  │
│   ├── 无极画笔交互（PathBrushTracker）             │
│   ├── 连续路径预览（StrokeCap.round 粗线）         │
│   └── 笔刷光标（白线圆）                           │
├──────────────────────────────────────────────────┤
│ State: spot_heal_state.dart                      │
│   ├── SpotHealMode { inactive, active }           │
│   ├── SpotHealState (brushRadius, brushHardness)  │
│   └── SpotHealNotifier → params.spotHealMarks     │
├──────────────────────────────────────────────────┤
│ Model: spot_heal_model.dart                      │
│   └── SpotHealMark { target, radius, hardness }   │
├──────────────────────────────────────────────────┤
│ Layer: spot_heal_layer.dart (Compose)             │
│   ├── marks → BrushStrokes → BrushRasterizer     │
│   ├── mask 纹理光栅化                              │
│   └── 单 shader pass（mask + 原图）               │
├──────────────────────────────────────────────────┤
│ Shader: spot_heal.frag → spot_heal.shader        │
│   ├── 输入: uImage + uMask + uSize + uHardness    │
│   ├── 16 向射线搜索 mask 边界                      │
│   └── IDW (1/d²) 加权填充                         │
└──────────────────────────────────────────────────┘
```

### 2.1 管线位置

```
源图 → 降噪 → 镜头校正 → Develop → Mask → Compose(spotLayer → healLayer → spotHealLayer)
     → 透视 → 裁剪 → 锐化 → 输出
```

### 2.2 文件清单

| 文件 | 职责 |
|------|------|
| `lib/brushes/spot_heal/spot_heal_model.dart` | SpotHealMark 数据模型 |
| `lib/brushes/spot_heal/spot_heal_state.dart` | SpotHealNotifier + SpotHealState |
| `lib/brushes/spot_heal/spot_heal_overlay.dart` | 无极画笔交互 + 连续路径 Canvas 预览 |
| `lib/brushes/spot_heal/spot_heal_section.dart` | UI 面板（激活/半径/硬度/清除） |
| `lib/brushes/spot_heal/spot_heal_layer.dart` | Compose 图层：mask 光栅化 + shader 调用 |
| `lib/brushes/spot_heal/spot_heal_cache.dart` | 两级缓存（marks hash + 增量滚动） |
| `e4pix_shader/assets/shaders/spot_heal.frag` | Shader 源码 |
| `assets/shaders/spot_heal.shader` | 编译二进制 |

## 3. Shader 算法

### 3.1 算法流程

```
对 mask 内每个像素:
  1. 3×3 邻域采样 → distToEdge (0=深内部, 1=边缘)
  2. hardness 混合: blendFactor = 1 - smoothstep(0, 1, distToEdge × (2 - h × 1.5))
  3. 16 向射线搜索 (max 150px):
     沿每个方向步进，找到 mask < 0.1 的边界像素
     采样 uImage 在该位置的颜色
  4. IDW 加权: fillCol = Σ(bCol / dist²) / Σ(1 / dist²)
  5. output = mix(src, fillCol, blendFactor)
```

### 3.2 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| N_RAYS | 16 | 搜索方向数 |
| MAX_STEPS | 150 | 每射线最大搜索像素 |
| 权重函数 | 1/d² | 近边界权重大，远边界权重小 |
| 羽化 | 3×3 smoothstep | 基于 mask 邻域距离 |

### 3.3 为什么是 mask 而非离散圆

- 离散圆叠加方案：涂抹路径 → 密集小圆 → shader 逐圆 IDW 填充。问题是圆重叠处效果不好，每个圆独立渲染于 base → compose 时后层未修改像素覆盖前层
- Mask 方案：涂抹路径 → 光栅化为一整张 mask 纹理 → shader 单 pass 处理整个 mask 区域 → 边界采样从 mask 外开始，避免重叠问题

## 4. 交互设计

### 4.1 无极画笔

- `PathBrushTracker(spacing: 0.005)` 均匀采样路径点
- 笔刷预览：连续粗线路径（`PaintingStyle.stroke` + `StrokeCap.round` + `strokeWidth = radius × 2 × displayWidth`），与 Detail 笔刷同款
- 光标：白线圆（`strokeWidth: 1.5, color: 0xFFFFFFFF`）
- 松手后一次批量提交所有 marks

### 4.2 坐标系统

- **SpotHealMark.target**：归一化 [0..1] 全图坐标
- **radius**：归一化值，UI 显示值 = radius × 1000（单位 ‰），默认 20
- **hardness**：0..1，默认 1.0（硬边）。shader 中硬边 blend = 1.0

## 5. Compose 图层注册

污点修复通过 `SpotHealLayerProvider` 接入 Compose 系统：

```dart
// multi_pass_preview.dart (自动注册，新画笔只需加这一行)
final spotHealProgram = ref.read(spotHealShaderProgramProvider).value;
if (spotHealProgram != null) {
  _spotHealLayer ??= SpotHealLayerProvider(program: spotHealProgram);
  providers.add(_spotHealLayer!);
}
```

所有通路（预览/导出/水印/分割对比）自动生效，无需额外改动。

## 6. 已知局限

- **射线搜索上限 150px**：大 mask 区域 > 150px 宽的内部像素可能找不到边界（`totalWeight == 0`），回退到原始像素
- **边界 clamp**：mark 靠近图像边缘时，边界采样点被 clamp 到图像边缘，可能引入边缘重复采样
- **性能**：16 rays × max 150 steps × mask 像素数。大 mask 区域（> 10000px²）可能慢
