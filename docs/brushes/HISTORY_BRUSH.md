# 历史记录画笔 (History Brush) 技术文档

## 1. 功能概述

基于 GPU shader 的 Photoshop 风格历史记录画笔，从 History 面板中选中的冻结快照恢复像素到当前画面。用户自由涂抹，涂抹区域被还原到选定历史状态。

- **操作方式**：在 History 面板选快照作为源 → 激活画笔 → 直接涂抹
- **交互模式**：无极画笔，自由路径，同 A 类（Stamp）committed preview 机制
- **核心效果**：shader 从冻结快照纹理采样 `target` 处像素，羽化混合到当前图像
- **无 clone source**：与图章/修复画笔不同，历史画笔不需要 Alt+取样——源是整个快照图像，从 target 同位置采样

与图章、修复画笔的对比：

| | 图章 | 修复画笔 | 历史画笔 |
|---|---|---|---|
| 源 | 手动 Alt+取样点 | 手动 Alt+取样点 | **冻结快照（整图）** |
| 采样方式 | source = target + offset | source = target + offset | **source = target（同位置）** |
| 算法 | 直接克隆 | 频域混合 | **直接克隆（快照→当前）** |
| 快照依赖 | 无 | 无 | **必须选中历史快照** |
| Committed preview | ✅ | ✅ | ✅ |

## 2. 架构

历史画笔按 A 类（Stamp）架构开发，继承 `BaseStampOverlayState`，使用 `StampGestureHandler` 和 `StampCompositor`：

```
┌──────────────────────────────────────────────────┐
│ Overlay: history_brush_overlay.dart              │
│   ├── 继承 BaseStampOverlayState<HistoryMark>     │
│   ├── 无极画笔交互（StampGestureHandler）          │
│   ├── Committed preview（StampCompositor）        │
│   └── getHistorySourceImage → 注入快照源          │
├──────────────────────────────────────────────────┤
│ State: history_brush_state.dart                  │
│   ├── HistoryBrushMode { inactive, active }       │
│   ├── HistoryBrushState (brushRadius,             │
│   │   brushHardness)                              │
│   └── HistoryBrushNotifier → params.brushMarks    │
├──────────────────────────────────────────────────┤
│ Model: history_brush_model.dart                  │
│   └── HistoryMark { target, radius, hardness,    │
│       createdAt }                                 │
│       source == target（无偏移）                   │
├──────────────────────────────────────────────────┤
│ Layer: history_brush_layer.dart (Compose)         │
│   ├── 批量打包 marks → 编码到纹理                  │
│   ├── 从 historyBrushSnapshot 读取源纹理           │
│   └── 单 shader pass（快照纹理 + mark 纹理）       │
├──────────────────────────────────────────────────┤
│ Shader: history_brush.frag                        │
│   ├── 输入: uImage + uHistorySrc + uMarksTex      │
│   │        + uSize + uHardness + uCount           │
│   ├── 逐 mark 从历史快照采样                        │
│   └── 羽化混合到当前图像                            │
└──────────────────────────────────────────────────┘
```

### 2.1 管线位置

```
源图 → 降噪 → 镜头校正 → Develop → Mask
     → Compose(图章 → 修复画笔 → 污点修复 → 加深减淡 → 海绵 → 历史画笔)
     → 透视 → 裁剪 → 锐化 → 输出
```

### 2.2 快照注入

```
HistoryPanel → 用户点击快照
  → historyBrushSnapshot.value = 冻结的 ui.Image
    → HistoryBrushOverlay.onInitState
      → compositor.getHistorySourceImage = () => historyBrushSnapshot.value
        → compositor.triggerComposite → shader pass 用此纹理采样
```

快照由 `HistoryPanel` 管理，是一个 `ValueNotifier<ui.Image?>`。用户切换快照时，compositor 自动在新 pass 中使用新快照。

### 2.3 文件清单

| 文件 | 职责 |
|------|------|
| `lib/brushes/history_brush/history_brush_model.dart` | HistoryMark 数据模型（source==target） |
| `lib/brushes/history_brush/history_brush_state.dart` | HistoryBrushNotifier + HistoryBrushState |
| `lib/brushes/history_brush/history_brush_overlay.dart` | A 类 overlay：手势委托 + compositor + 快照注入 |
| `lib/brushes/history_brush/history_brush_section.dart` | UI 面板（激活/半径/硬度/清除） |
| `lib/brushes/history_brush/history_brush_layer.dart` | Compose 图层：marks→纹理 + 快照 shader pass |
| `assets/shaders/brushes/history_brush.frag` | Shader 源码 |

## 3. Shader 算法

### 3.1 算法流程

```
对每个 mark（最多 MAX_MARKS 个）:
  1. 计算目标像素到 mark 中心的归一化距离 d
  2. 边缘羽化: blend = smoothstep 或 step（取决于 hardness）
  3. 从 uHistorySrc 纹理在 target 位置采样颜色 historyCol
  4. 混合: output = mix(current, historyCol, blend)
```

与图章的核心区别：图章的采样位置 = `target + sourceOffset`（从 `source` mark 坐标偏移），历史画笔的采样位置 = `target`（同位置）。

### 3.2 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| MAX_MARKS | 128 | 每 pass 最大 mark 数（Dart 端 `_kMaxSpots` 必须同步） |
| 编码 | `encodeMarksToTexture()` | marks 打包到 RGBA16 纹理，shader 侧 `unpackMarks()` 解码 |
| 采样 | 快照纹理 `uHistorySrc` | 直接从快照 target 位置读取，无偏移 |
| 羽化 | smoothstep / step | hardness ≥ 0.999 时走 step（硬边），否则 smoothstep |

### 3.3 数据编码

marks 通过 `encodeMarksToTexture()` 打包为 RGBA16 纹理传给 shader：

```
每个 mark 占 3 个 vec4:
  slot[0] = (target.x, target.y, radius, hardness)
  slot[1] = (source.x, source.y, 0, 0)  ← History: source == target
  slot[2] = (0, 0, 0, 0)
```

虽然 `HistoryMark.source == target`，但编码为 3-slot 格式保持与图章 shader 接口兼容。

## 4. 交互设计

### 4.1 激活流程

```
1. History 面板: 用户点击某条历史记录 → historyBrushSnapshot 设定
2. UI 面板: 用户点击 History Brush 按钮 → mode = active
3. 图像上: 无极画笔涂抹 → StampGestureHandler 生成 marks（_strokeTimestamp 统一）
4. 松手: commit → persist → triggerComposite（GPU 预览+管线渲染）
```

### 4.2 Committed Preview

与图章/修复画笔同款机制：
- `StampCompositor.triggerComposite()` 在笔画进行中实时合成预览
- `hashHistoryMarks()` 对比 committed marks 与当前 marks，匹配则跳过重合成
- `handleMarksCleared()` 清除所有 marks 时重置 compositor

### 4.3 坐标系统

- **HistoryMark.target**：归一化 [0..1] 全图坐标
- **HistoryMark.source**：恒等于 target（无偏移，从快照同位置采样）
- **radius**：归一化值，默认 0.02
- **hardness**：0..1，默认 1.0（硬边）

### 4.4 快照生命周期

| 事件 | 行为 |
|------|------|
| 用户切换快照 | compositor 下次 pass 使用新快照（`getHistorySourceImage` 动态读取） |
| 快照被释放 | compositor 跳过合成，管线 pass 中 marks 不生效 |
| 参数切换 | compositor 检测到参数变化 → force: true 重合成 |
| 源图变化 | `didUpdateWidget` 检测 → `disposeComposited` + 重置 |

## 5. Compose 图层注册

历史画笔通过 `HistoryBrushLayerProvider` 接入 Compose 系统——与其他画笔同样模式，所有通路自动生效。

时间排序渲染：多画笔共存时按 `createdAt` 全局排序，跨画笔交替绘制自动按实际顺序叠加。

### 5.1 快照缺失处理

```dart
// history_brush_layer.dart
Future<BrushLayer> render(...) async {
  final historySrc = historyBrushSnapshot.value;
  if (historySrc == null) return BrushLayer.empty(id);  // 无快照 → 空图层
  // ... 正常渲染
}
```

如果用户未在 History 面板选中快照，图层返回空——不影响其他画笔的正常渲染。

## 6. 与其他 A 类画笔的差异

| | 图章 | 修复画笔 | 历史画笔 |
|---|---|---|---|
| clone source | Alt+取样点 | Alt+取样点 | **无（快照整个图）** |
| paintOffset | target → source | target → source | **无（source==target）** |
| getCloneSource | 返回取样点 | 返回取样点 | **返回 Offset.zero** |
| getIsSampling | 是（Alt 模式） | 是（Alt 模式） | **否（永远绘画）** |
| getHistorySourceImage | null | null | **historyBrushSnapshot.value** |
| warmup 条件 | 始终 | 始终 | **快照非空才预热** |

## 7. 已知局限

- **快照不持久化**：`historyBrushSnapshot` 是内存中的 `ValueNotifier<ui.Image?>`，app 重启后需重新选择快照
- **快照纹理绑定**：shader pass 期间快照纹理必须保持存活，`compositor` 通过闭包持有引用
- **marks 加载后需重选快照**：sidecar 反序列化 history brush marks 后，用户需重新在 History 面板点击快照才能正常渲染
- **无批量 pass**：与图章同款逐 mark shader 循环，单 pass 最多 128 marks
