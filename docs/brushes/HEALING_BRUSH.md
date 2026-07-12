# 修复画笔 (Healing Brush) 技术文档

## 1. 功能概述

修复画笔是 e4pix 的第二个像素级画笔工具，目标与 PS 修复画笔 (Healing Brush) 行为一致：

- **操作方式**：Alt+点击 / 取样按钮 → 设置克隆源点 → 点击/拖拽涂抹
- **核心效果**：将源点区域的纹理（高频细节）迁移到目标区域，同时保留目标区域的色彩/亮度背景（低频色），实现"纹理来自源、光照来自目标"
- **与图章的区别**：图章 (Clone Stamp) = `直接复制源像素`；修复画笔 = `频率分离后纹理迁移`

当前状态：v7 边界匹配修复 (Boundary-Matched Healing) 已匹敌 PS 效果，主流场景（白碗修黑点）可彻底消除缺陷。预览 WYSIWYG 已通过 committed preview 持久化实现。

## 2. 架构

修复画笔按 8 步清单开发，完全镜像图章 (Spot Removal) 的结构层模式：

```
┌──────────────────────────────────────────────────┐
│ Overlay: healing_overlay.dart                    │
│   ├── 手势处理 (screenToSourceNorm / 坐标变换)    │
│   ├── 笔画采样 (PathBrushTracker)                 │
│   ├── 即时预览 (_HealingPainter → Canvas 克隆圆) │
│   └── Committed Preview (防闪屏，hash 匹配清除)   │
├──────────────────────────────────────────────────┤
│ State: healing_state.dart                        │
│   ├── HealingMode { inactive, active }           │
│   ├── HealingState (cloneSource, radius, hardness)│
│   └── HealingNotifier → params.brushMarks['healing'] │
├──────────────────────────────────────────────────┤
│ Model: healing_mark.dart                         │
│   └── HealingMark { source, target, radius, hardness } │
├──────────────────────────────────────────────────┤
│ Render: full_pipeline_renderer.dart               │
│   ├── _runHealingPass() — 64 marks/batch         │
│   ├── Healing inline section (Spot Removal 之后) │
│   └── HealingCache (两级缓存)                     │
├──────────────────────────────────────────────────┤
│ Shader: healing.frag                       │
│   ├── 64 marks × 6 uniforms = 387 floats         │
│   └── applyHeal() — 频率分离 / 边界引导          │
└──────────────────────────────────────────────────┘
```

### 2.1 管线位置

```
源图 → 降噪 → 镜头校正 → Develop → Mask → Spot Removal → Healing → 透视 → 裁剪 → 锐化 → 输出
```

### 2.2 与图章 (Spot Removal) 的代码共享度

| 层级 | 共享度 | 说明 |
|------|--------|------|
| 工具层 | 100% | `brush_coord_utils` / `brush_preview_utils` / `PathBrushTracker` / `TextureNotifier` 全部复用 |
| 结构层 | ~80% | Overlay / State / Cache / Section 均为 copy-paste-adapt |
| Shader 层 | 结构相同 | 64 marks / 387 uniforms / batch 循环完全相同，仅 `applyHeal` 内核不同 |

遵循"2 个实例保持重复，3 个再提取"规则。

## 3. Shader 算法迭代

### 3.1 算法历史

| 版本 | 算法 | 效果 | 问题 |
|------|------|------|------|
| v1 | 5×5 盒式平均频率分离 | 褪色投影感 | 盒式平均太粗暴，丢失自然纹理 |
| v2 | 色彩平移 `srcColor + (tgtCenter - srcCenter)` | 白碗场景：黑色晕染 | 目标圆心=缺陷本身，参考色错误 |
| v3 | 边界引导纹理迁移 `boundaryRgb + (srcPixel - srcCentre)` | 小半径需多次涂抹 | 1.15×r 偏移不够远 |
| v4 | 边界亮度缩放 `srcPixel × (boundaryLuma / srcLuma)` | 纯色区正确 | 纹理区信息丢失 |
| v5 | 中心克隆+边缘混合 `mix(boundaryRgb, srcPixel, blend)` | WYSIWYG, 纯色正确 | 无纹理迁移，和图章差异小 |
| v6 | 5×5 Gaussian 频率分离 `tgtLow + (srcPixel - srcLow)` | 黑点只能淡化 | tgtLow 含缺陷像素 | 继续尝试 |
| **v7** | **边界采样 + 色彩校正 `srcPixel + (tgtBg - srcBg)`** | **匹敌 PS** | **25 采样/px，边界绕开缺陷** | **当前** |

### 3.2 当前算法 (v7) — 边界匹配修复

```
每 mark：
  srcBg = 沿源点圆周采样 12 点取平均（干净背景色，绕开缺陷）
  tgtBg = 沿目标圆周采样 12 点取平均
  colourShift = tgtBg - srcBg              // 全局光照补偿

圆内每像素：
  srcPixel = texture(对应源位置)
  corrected = clamp(srcPixel + colourShift, 0, 1)
  output = mix(original, corrected, hardness_blend)
```

**为什么有效**：
- 边界采样在缺陷**外侧** → `tgtBg` 不会被黑点污染
- 同背景色时 → `colourShift ≈ 0` → 纯克隆 → 彻底消除缺陷
- 中心输出 = 克隆像素 = overlay 预览 → WYSIWYG
- 每像素 25 次纹理采样（v6 为 50 次）

**`sampleBoundary()`**：12 个等角度点（30° 间隔），clamp 到图像边界防 OOB。

### 3.3 与 PS 的对比

| PS 修复画笔 | v7 |
|------------|-----|
| 多分辨率金字塔频率分离 | 边界采样 + 全局色彩校正 |
| 自适应内核大小 | 固定 12 点边界采样 |
| 色彩空间变换 + 亮度匹配 | RGB 空间直接校正 |
| WYSIWYG | WYSIWYG（中心=克隆） |

## 4. Shader 编译流程

**关键规则**：编译在主项目根目录执行，`pubspec.yaml` 的 `shaders:` 段已声明全部 `.frag` 文件。

```bash
flutter build bundle
cp build/flutter_assets/assets/shaders/brushes/healing.frag assets/shaders/brushes/healing.shader
```

- `.frag` 源码：`assets/shaders/brushes/healing.frag`（git 追踪）
- 编译产物：`build/flutter_assets/assets/shaders/brushes/healing.frag`（IPLR 二进制，魔数 `IPLR`）
- 部署：手动重命名 `.frag` → `.shader` 后放入 `assets/shaders/brushes/`
- 运行时加载：`brushShaderProgramsProvider`（统一管理所有 brush shader）
- **不要用 `impellerc`**——直接编译产出的格式与 `FragmentProgram.fromAsset` 不兼容

## 5. 文件清单

| 文件 | 职责 |
|------|------|
| `lib/core/models/healing_mark.dart` | HealingMark 数据模型 |
| `lib/core/models/adjustment_params.dart` | brushMarks map（统一聚合，key='healing'）(序列化/undo) |
| `lib/state/tools/healing_state.dart` | HealingNotifier + HealingState + healingStateProvider |
| `lib/state/render/render_state.dart` | healingShaderProgramProvider + renderedHealingHashProvider |
| `lib/render/healing_cache.dart` | 两级缓存 (marks hash + 增量滚动) |
| `lib/render/full_pipeline_renderer.dart` | _runHealingPass() + healing 内联段落 |
| `lib/render/pass_config.dart` | hasHealingMarks() + needsFullPipeline() |
| `lib/widgets/develop/sections/healing_overlay.dart` | 手势 + Canvas 预览 + committed preview |
| `lib/widgets/develop/sections/healing_section.dart` | UI 面板：激活/取样/半径/硬度/清除 |
| `lib/widgets/develop/vertical_adjustment_panel.dart` | 竖屏第 9 tab (13 tabs) |
| `lib/widgets/develop/horizontal_adjustment_panel.dart` | 横屏 rail item + switch case |
| `lib/widgets/preview/preview_area.dart` | HealingOverlay 叠加 + healingProgram 传入 |
| `lib/widgets/preview/multi_pass_preview.dart` | healingProgram/_healingCache 参数 + hash 更新 |
| `lib/state/tools/develop_tool_state.dart` | DevelopTool.healing 枚举 |
| `lib/state/providers.dart` | 导出 healing_state.dart |
| `lib/widgets/develop/develop_sections.dart` | 导出 healing_section.dart |
| `assets/shaders/brushes/healing.frag` | Shader GLSL 源码（编译：主项目 `flutter build bundle`） |
| `assets/translations/en-US.json` | 英文翻译 (healing* 前缀) |
| `assets/translations/zh-CN.json` | 中文翻译 |

## 6. 已知问题

### 6.1 修复效果 — 已解决 (v7)

v7 边界匹配修复算法已匹敌 PS 效果。白碗修复黑点场景可彻底消除缺陷。

### 6.2 预览与管线 — 已解决

v7 中心输出 = 克隆像素 = overlay 预览，配合 committed preview 持久化（切换工具时静态字段保存未渲染预览），WYSIWYG 已实现。

### 6.3 重叠笔画预览不准（与图章 P1 相同问题）

**现象**：一笔内多个 marks 互相重叠时，Canvas 预览从静态 `sourceImage` 采样，看不到前面 marks 的修改。松手后管线批次渲染 → 结果正确。

**根因**：overlay 机制的根本限制——所有 marks 从同一张静态 pre-stroke 图像采样。

**修复方向**：维护增量累积缓冲区，复杂度高。可延后。

## 7. 其他相关改动

- Compose shader 已删除——当时过早设计，两个画笔都走内联渲染，图层化延后
- 图章 (Spot Removal) 已从 UI 改名 "Clone Stamp / 图章"
- 内部变量名保留 `SpotMark` / `spotRemoveStateProvider`（仅 UI 文字改名）
- `_kMaxSpots = _kMaxMarks = 64`（批大小上限，128 触发 Windows TDR 超时）
