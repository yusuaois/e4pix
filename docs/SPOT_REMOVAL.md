# 污点修复（Spot Removal）模块技术文档

## 1. 功能概述

基于 GPU shader 的仿制图章（Clone Stamp）工具。用户在图像上取样一个源点，然后在目标区域涂抹，shader 将源点周围的像素克隆到目标位置，实现污点/瑕疵修复。

交互模式遵循 Photoshop 仿制图章：Alt+点击取样 → 涂抹绘画，源点和目标点保持固定偏移同步移动。

## 2. 文件清单

| 类别 | 文件 | 职责 |
|------|------|------|
| 数据模型 | `lib/core/models/spot_mark.dart` | 单个污点标记：source、target、radius、hardness |
| 状态管理 | `lib/state/tools/spot_remove_state.dart` | 画笔状态（brushRadius、brushHardness、cloneSource、spots 列表） |
| 交互覆盖层 | `lib/widgets/develop/sections/spot_remove_overlay.dart` | 手势处理（取样/绘画）、Canvas 即时预览、坐标变换 |
| 设置面板 | `lib/widgets/develop/sections/spot_remove_section.dart` | 画笔半径/硬度滑块、取样按钮 |
| 画笔工具 | `lib/utils/path_brush_tracker.dart` | 路径均匀采样，间距 = radius × 0.5 |
| Shader 源码 | `e4pix_shader/assets/shaders/spot_remove.frag` | GLSL Fragment Shader，每 spot 6 uniform（srcX/Y, tgtX/Y, r, h） |
| Shader 编译产物 | `assets/shaders/spot_remove.shader` | Flutter runtime effect 编译输出 |
| 渲染缓存 | `lib/render/spot_removal_cache.dart` | 两级缓存：spots-hash + 增量滚动 |
| 管线渲染 | `lib/render/full_pipeline_renderer.dart` | 管线中 spot removal pass 的执行与循环 |
| 渲染状态 | `lib/state/render/render_state.dart` | developOutputProvider、renderedSpotsHashProvider 等 |
| 预览组件 | `lib/widgets/preview/preview_area.dart` | 主预览区（overlay 使用 developOutput） |
| 多 pass 预览 | `lib/widgets/preview/multi_pass_preview.dart` | 离屏全管线渲染，管理缓存生命周期 |
| 水印预览 | `lib/widgets/preview/watermark_preview.dart` | 水印/边框预览（需全管线渲染） |
| 导出 | `lib/render/exporter.dart` | 导出时使用 full pipeline（含 spot removal） |

## 3. 架构与数据流

### 3.1 交互流程

```
用户取样（Alt+点击 / 取样按钮）
  → setCloneSource(samplePos)    // 设置源点
  → _paintOffset = null          // 重置偏移

用户下笔（绘画模式）
  → _onPanStart: 建立 _paintOffset = cloneSource - firstTarget
  → _onPanUpdate: PathBrushTracker 生成均匀采样点
                 每个点 source = target + paintOffset
                 积攒在本地 _strokeSpots（不触发管线）
  → _onPanEnd: addSpotsBatch() → 一次性提交给管线
               committedPreview 保留本地预览直到管线完成

管线渲染（异步）
  → FullPipelineRenderer.render()
  → Develop → Mask → Spot Removal → 透视 → 裁剪 → 锐化
  → 产出 PipelineRenderResult(finalImage, developOutput)
  → 更新 renderedSpotsHashProvider → overlay 比对 hash 清除预览
  → 更新 developOutputProvider → 下次 overlay 预览使用含污点修复的图像
```

### 3.2 坐标系统

- **SpotMark.source / target**：归一化 [0..1] 全图坐标（与 LibRaw 解码尺寸对应）
- **radius**：归一化值，相对于源图宽度。默认 0.02 = 源图宽度的 2%
- **画笔 UI 显示**：`brushRadius * 1000`，默认值 20

Overlay 中的坐标变换函数（均在 `spot_remove_overlay.dart` 文件顶部）：

| 函数 | 方向 | 用途 |
|------|------|------|
| `screenToSourceNorm()` | 屏幕像素 → 全图归一化 | 点击位置转源图坐标 |
| `sourceToScreenNorm()` | 全图归一化 → 屏幕像素 | cloneSource 十字线显示 |
| `sourceRadiusToScreen()` | 全图归一化半径 → 屏幕像素半径 | 圆圈大小计算 |

**⚠️ 变换中使用了 `CropParams`（裁剪/旋转/翻转），确保 overlay 预览与裁剪后的画面一致。**

## 4. Shader 详解

### 4.1 Uniform 布局

每 batch 最多 32 个 spot，每个 spot 6 个 float：

```
索引 0:   uSize.x (输出宽度)
索引 1:   uSize.y (输出高度)
索引 2:   uSpotCount (当前 batch 的 spot 数量)
索引 3-8:   uSpot0 (srcX, srcY, tgtX, tgtY, radius, hardness)
索引 9-14:  uSpot1
...
索引 189-194: uSpot31
总计: 2 + 1 + 32×6 = 195 个 float
```

断言校验：`assert(i == 2 + 1 + _kMaxSpots * _kSpotUniformsPerSpot)`，即 `assert(i == 195)`。

### 4.2 逐像素计算（`applySpot` 函数）

```
1. Early exit: enabled < 0.5 → 跳过（batch 空槽）
2. AABB 粗筛: |uv - tgt| > (r, r×aspect) → 跳过
3. 距离计算: d = length((uv.x - tgt.x) × aspect, uv.y - tgt.y)
4. 混合权重: blend = 1 - smoothstep(r×h, r, d)  或  h≥0.999 时用 step
5. blend < 0.001 → 跳过（圈外像素不采样纹理）
6. OOB 检查: sampleUV 超出 [-0.001, 1.001] → 保持原色
7. 混合: mix(原色, texture(sampleUV), blend)
```

### 4.3 ⚠️ 硬度 1.0 的 smoothstep 陷阱

当 `hardness = 1.0` 时，`inner = r × 1.0 = r`，即 `smoothstep(r, r, d)`，两个边界参数相等。

**GLSL 规范中 `smoothstep(edge, edge, x)` 是未定义行为**。不同 GPU 对此处理不同：
- 部分 GPU 返回正确的 step 函数（`d < r → 0, d ≥ r → 1`）
- 部分 GPU 返回垃圾值（导致 AABB 矩形内全部像素被替换 → 方形污点）

**修复**：硬度 ≥ 0.999 时使用 `step(r, d)` 替代 `smoothstep(r, r, d)`：

```glsl
float blend = (h >= 0.999)
    ? (1.0 - step(r_corrected, d))
    : (1.0 - smoothstep(inner, r_corrected, d));
```

### 4.4 OOB 边界检查

```glsl
if (sampleUV.x < -0.001 || sampleUV.x > 1.001 ||
    sampleUV.y < -0.001 || sampleUV.y > 1.001) {
    return col;  // 保持原色，不拉伸边缘像素
}
```

使用 epsilon（±0.001）而非严格边界（0.0/1.0），防止浮点精度导致 1px 边缘误判。

## 5. 两级缓存策略

文件：`lib/render/spot_removal_cache.dart`

### 第一级 — Spots Hash 缓存

- **触发**：参数滑块拖动（develop 参数变化但 spots 未变）
- **Key**：`Object.hashAll(spots.map((s) => s.hashCode))`
- **命中效果**：0 个 GPU pass，直接复用上次 spot removal 结果
- **失效**：`invalidateSpotsCache()`（拖动结束）、`invalidate()`（换图）

### 第二级 — 增量滚动缓存

- **触发**：同一组 develop 参数下新增更多 spots（新描边）
- **Key**：`(developFingerprint, spotCount)`
- **命中效果**：从上次中断的 index 继续渲染，O(新增数/32) 而非 O(N/32)
- **失效**：develop 参数变化（devKey 不匹配）、spotCount 回退

### 缓存查询优先级

```
1. getFromSpotsCache(spots) → 命中 → 直接返回（0 pass）
2. getIncremental(devKey, allSpots) → 命中 → 从中间 index 继续（增量 pass）
3. 全量重算：develop 参数变化且无增量缓存
```

### 缓存所有权

`getFromSpotsCache` 和 `getIncremental` 返回 clone，调用方拥有返回图像的所有权，无需再 clone。缓存内部通过 `putSpotsCache` / `putRolling` 存储新结果的 clone，独立管理。

## 6. Overlay 预览机制

### 6.1 两层预览

| 预览层 | 绘制时机 | 数据来源 | 绘制方法 |
|--------|---------|---------|---------|
| 笔画内预览 | 拖拽中每帧 setState | `_strokeSpots`（本地列表） | `_drawStrokeSpot`：clipOval + drawImageRect |
| 已提交预览 | 松手后管线渲染完成前 | `_committedPreview`（交由 painter） | 同上 |
| 悬停预览 | 未按下时 | `sourceImage`（developOutput） | `_drawPreviewCursor`：硬边用 clipOval，柔边用 saveLayer + 渐变蒙版 |

### 6.2 Committed Preview 生命周期

```
松手 → addSpotsBatch() → 记录 _committedSpotsHash
     → _committedPreview.addAll(_strokeSpots)
     → _strokeSpots.clear()

管线渲染完成 → renderedSpotsHashProvider 更新
             → overlay listener 比对 hash
             → 匹配 → _committedPreview.clear()
             → 不匹配 → 保持（防止无关渲染误清除）
```

**⚠️ 关键设计**：使用 `renderedSpotsHashProvider`（hash 匹配）而非简单的 generation counter。因为参数滑块拖动也会触发管线渲染，但此时不应清除 committed preview（hash 不匹配）。

### 6.3 OOB 比例映射

当采样源靠近图像边缘时，采样矩形可能部分超出图像边界。Overlay 使用 `_computeOOBRects()` 处理此情况：

1. 计算采样区域与图像边界的交集（`clamp`）
2. 将交集在原始正方形中的相对位置按比例映射到目标圆内
3. 交集为空（完全在界外）→ 跳过绘制
4. 交集非空 → 只绘制有效像素区域，界外部分透明

`_computeOOBRects` 是 `_drawStrokeSpot` 和 `_drawPreviewCursor` 共用的辅助方法，返回 record `({Rect srcRect, Rect dstRect, Rect fullDstRect})`。

## 7. GPU 资源管理

### 7.1 Spot Removal Pass 中的内存安全

`full_pipeline_renderer.dart` 中 for 循环处理 batch：

```dart
for (int i = startIdx; i < spots.length; i += 32) {
    try {
        final result = await _runSpotRemovePass(input: batchInput, ...);
        if (batchInputOwned) batchInput.dispose();  // 释放旧 batch
        batchInput = result;
        batchInputOwned = true;
    } catch (e) {
        if (batchInputOwned) batchInput.dispose();  // ⚠️ 异常时也释放
        rethrow;
    }
}
```

**设计要点**：内层 try-catch 确保即使 `_runSpotRemovePass` 抛异常（如 GPU OOM），已分配的 `batchInput` 也被正确释放。`rethrow` 保持异常传播到外层 catch（仅打日志，不崩溃）。

### 7.2 developOutput 生命周期

`developOutputProvider` 使用 `DevelopOutputNotifier`（Notifier 模式）管理 GPU 纹理：

- `update(newImage)`：保存新纹理 → 旧纹理延迟一帧 dispose（`addPostFrameCallback`）
- 延迟 dispose 是为了避免 GPU 并发冲突（旧纹理可能仍在当前帧被 overlay 读取）
- 调用方只需 `ref.read(developOutputProvider.notifier).update(image)`，无需手动管理

## 8. 画笔偏移（PS Clone Stamp 行为）

### 8.1 偏移的建立与保持

```
取样: cloneSource = A, _paintOffset = null

第一笔下笔: _paintOffset = A - B
  笔画内: source = target + (A - B)   // 源点跟随目标点同步移动

后续下笔: source = target + _paintOffset   // 保持原始偏移
  不再从 cloneSource 读取（避免漂移累积）
```

### 8.2 ⚠️ 常见的错误实现

**错误做法 1**：`_paintOffset ??= ...` 一次性赋值 → 重新取样后旧偏移残留

**已修复**：重新取样时 `_paintOffset = null`，下次下笔重新计算。

**错误做法 2**：`_onPanStart` 从 `state.cloneSource`（已漂移）读取第一笔 source

**已修复**：已有偏移时从 `target + paintOffset` 反算 source，保持偏移一致性。

## 9. 管线集成要求

### 9.1 管线顺序

```
Develop → Mask（局部调整） → Spot Removal → 透视 → 裁剪 → 锐化
```

**⚠️ Mask 在 Spot Removal 之前**：污点修复从已遮罩的图像采样，避免在遮罩区域看到被遮罩覆盖的原始污点。如果修改顺序，需同步更新 `developOutput` 的捕获时机。

### 9.2 使用 Full Pipeline 的组件

以下组件使用全管线渲染（含 spot removal），修改管线时需同步验证：

| 组件 | 文件 |
|------|------|
| 主预览区 | `preview_area.dart`（`needFullPipeline` 门控） |
| 多 pass 预览 | `multi_pass_preview.dart`（`FullPipelineRenderer.render()`） |
| 水印/边框预览 | `watermark_preview.dart`（`_ComplexImageLayer` → `MultiPassPreview`） |
| 导出 | `exporter.dart` |
| AI 输入渲染 | `ai_input_renderer.dart` |
| 直方图 | `histogram_panel.dart` |
| 取色器 | `color_picker_overlay.dart` |

**⚠️ 新增使用渲染结果的组件时**：评估是否需要全管线（含 spot removal / mask / perspective），还是 develop-only 足够。参考 `watermark_preview.dart` 的 `needFullPipeline` 门控模式。

## 10. 已知问题与注意事项

### 10.1 Shader 编译

- 修改 `e4pix_shader/assets/shaders/spot_remove.frag` 后，必须在 `e4pix_shader/` 目录执行：
  ```bash
  flutter clean && flutter pub get && flutter build bundle
  ```
- 将编译产物复制到主项目：
  ```bash
  cp e4pix_shader/build/flutter_assets/assets/shaders/spot_remove.frag \
     assets/shaders/spot_remove.shader
  ```
- **⚠️ 不要用 `impellerc` 直接编译**

### 10.2 Uniform 断言

添加新 uniform 或修改 spot 结构时，必须同步更新 `full_pipeline_renderer.dart` 中的断言：
```dart
assert(i == 2 + 1 + _kMaxSpots * _kSpotUniformsPerSpot);
```

### 10.3 性能特征

- 0 spot：无额外开销
- 1-32 spots（参数不变）：spots hash 缓存命中，0 pass
- 新增 1-32 spots（同参数）：增量渲染，1 pass
- 参数变化 + 大量 spots：全量重算，O(N/32) passes

### 10.4 待提取的公共组件

以下方法/类可提取供未来其他画笔使用：

| 组件 | 位置 | 可复用场景 |
|------|------|-----------|
| `_computeOOBRects()` | `spot_remove_overlay.dart` | 任何需要圆形预览 + OOB 处理的画笔（修复画笔、加深减淡） |
| `PathBrushTracker` | `utils/path_brush_tracker.dart` | 任何需要沿路径均匀采样点的画笔 |
| `SpotRemovalCache` 模式 | `spot_removal_cache.dart` | 可抽象为 `IncrementalRenderCache<K, V>` 用于其他需要增量渲染的工具 |
| `DevelopOutputNotifier` 模式 | `render_state.dart` | 可提取为 `TextureNotifier` mixin，任何管理 GPU 纹理生命周期的 Provider 复用 |
| `screenToSource / sourceToScreen` | `spot_remove_overlay.dart` 顶部 | 任何需要在屏幕坐标和全图坐标间转换的工具 |
| `_drawStrokeSpot` 的 clipOval + drawImageRect 模式 | `spot_remove_overlay.dart` | 任何需要圆形硬边预览的画笔 |

### 10.5 水印预览注意事项

水印/边框预览的 `needFullPipeline` 门控必须与 `preview_area.dart` 保持一致。当前检查条件：
- `hasLocals`（局部调整）
- `hasSharpen`（锐化）
- `hasDenoise`（降噪）
- `hasSpots`（污点修复）
- `hasLensCorrection`（镜头校正）
- `hasPerspective`（透视）

`_ComplexImageLayer` 需要传入所有需要的 shader program（包括 `spotRemoveProgram`、`perspectiveProgram`、`lensCorrectProgram`）。
