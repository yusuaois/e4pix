# e4pix 渲染系统跨文件依赖规范

> 修改任何渲染相关文件前，必读此文档。
> 本文件记录了所有会导致联动 BUG 的跨文件依赖关系。

---

## 一、三种坐标系统

项目中存在三种坐标空间，混淆它们是导致 BUG 的首要原因。

| 坐标系 | 含义 | 使用者 |
|--------|------|--------|
| **全图坐标** (source) | 原始解码图像像素 | `baseRaster`、SAM/SmartRegion guide、`inverseMap` 返回值 |
| **oriented 坐标** | 经过 orientation + flip + straighten 后的图像 | `CropParams.x/y/width/height` 的参考空间 |
| **裁剪后输出坐标** (output) | 经过裁剪框裁剪后的最终图像 | 画笔笔触点、渐变蒙版坐标、shader uniform、UI 显示 |

### 关键规则

- `BrushStroke.points` → **输出空间** [0..1]
- `LinearGradientMask` / `RadialGradientMask` 坐标 → **输出空间** [0..1]
- `BrushMask.baseRaster` → **全图空间** (baseW × baseH 分辨率)
- SAM / SmartRegion guide → **全图空间**（用 `CropParams.identity` 渲染）
- SAM / SmartRegion seed → 屏幕点击是**输出空间**，需 `crop.outputToSourceOffset()` 转换

### 坐标变换方法（全在 `crop_params.dart`）

| 方法 | 方向 | 用途 |
|------|------|------|
| `inverseMap(ox, oy, outW, outH, srcW, srcH)` | 输出像素 → 全图浮点坐标 | `brush_rasterizer.dart` 采样 baseRaster |
| `outputToSourceNorm(nx, ny, srcW, srcH)` | 输出归一化 → 全图归一化 | seed 坐标变换 |
| `outputToSourceOffset(seed, srcW, srcH)` | 同上，Offset 版 | service 中直接调用 |

**⚠️ 所有裁剪逆变换数学必须集中在 `crop_params.dart`，不要在其他文件中手算。**

---

## 二、渲染管线顺序

`FullPipelineRenderer.render()` 中的处理顺序：

```
源图 → 降噪 → 镜头校正* → Develop(曝光/曲线/LUT/HSL/颗粒)
     → 透视 → 裁剪(applyCropTransform) → 蒙版(局部调整) → 锐化 → 输出
```

> \* 镜头校正的输出作为 Develop pass 的输入（`full_pipeline_renderer.dart:172 developPassInput`），不是完全独立的阶段。Develop pass 内部包含两个 LUT（A/B）和曲线纹理。

### 裁剪步骤的两个实现

| 文件 | 函数 | 方向 | 用途 |
|------|------|------|------|
| `crop_transform.dart` | `applyCropTransform()` | 正向 | 管线中物理裁剪图像 |
| `crop_params.dart` | `inverseMap()` | 逆向 | 蒙版光栅化中采样 baseRaster |

**两者互为逆运算，改一方必须验证另一方。**

---

## 三、蒙版系统跨文件依赖

### 3.1 蒙版类型与代码路径

| 蒙版类型 | 坐标系 | 光栅化方式 | 涉及文件 |
|----------|--------|-----------|----------|
| LinearGradientMask | 输出空间 [0..1] | GLSL shader uniform | `full_pipeline_renderer.dart` |
| RadialGradientMask | 输出空间 [0..1] | GLSL shader uniform | `full_pipeline_renderer.dart` |
| BrushMask (纯画笔) | 输出空间 [0..1] | GPU Canvas 路径 | `brush_rasterizer.dart` `_rasterizeGeometric` |
| BrushMask (有 baseRaster 或 autoMask) | 混合 | CPU 逐像素 | `brush_rasterizer.dart` `_rasterizeCpu` |

### 3.2 baseRaster 数据流

```
SAM/SmartRegion 生成蒙版（全图空间）
    → setBaseRaster(raster, gw, gh) 存入 BrushMask
    → 管线渲染时 rasterizeBrushMask(crop, srcW, srcH)
    → _rasterizeCpu 中 crop.inverseMap() 把输出像素映射回全图空间
    → 双线性采样 baseRaster
    → 输出裁剪后的蒙版图
```

**修改以下任何一个文件，必须同步验证其他文件：**

| 文件 | 改动类型 | 联动文件 |
|------|----------|----------|
| `crop_params.dart` inverseMap 数学 | 逆变换逻辑 | `brush_rasterizer.dart` 调用方 |
| `crop_transform.dart` 正向变换 | 正变换逻辑 | `crop_params.dart` 逆变换必须一致 |
| `brush_rasterizer.dart` 裁剪路径 | 采样逻辑 | `crop_params.dart` inverseMap、`full_pipeline_renderer.dart` 传参 |
| `segmentation_service.dart` guide 渲染 | 坐标系选择 | `crop_params.dart` outputToSourceOffset、`brush_rasterizer.dart` inverseMap |
| `smart_region_service.dart` guide 渲染 | 坐标系选择 | 同上 |
| `local_mask_overlay.dart` 预览 | 可视化逻辑 | `brush_rasterizer.dart`（调用 rasterizeBrushMask）、`crop_params.dart` |
| `mask_cache.dart` | 缓存失效 | `full_pipeline_renderer.dart` guideEpoch |

### 3.3 ⚠️ 画笔蒙版的裁剪修改检查清单

修改任何与裁剪相关的代码时，逐项检查：

1. **baseRaster 存储空间**：SAM/SmartRegion 的 guide 是否用 `CropParams.identity` 渲染？
2. **seed 坐标变换**：屏幕点击（输出空间）是否通过 `outputToSourceOffset` 转换到全图空间？
3. **inverseMap 越界保护**：straighten 旋转产生的黑角区域，`inverseMap` 返回的坐标可能超出源图范围，必须有 `ix < 0 || ix >= srcW` 检查
4. **管线传参**：`full_pipeline_renderer.dart` 是否传入 `crop: params.crop, srcW: sourceImage.width, srcH: sourceImage.height`？
5. **缓存透传**：`mask_cache.dart` 是否把 crop/srcW/srcH 透传给 `rasterizeBrushMask`？
6. **预览层**：`local_mask_overlay.dart` 的 `_rasterizeBaseViz` 是否也传入 crop 参数？
7. **预览层缓存 key**：是否包含 crop hash（不只 baseRaster identity）？

---

## 四、自动蒙版 (autoMask) 的 guide 坐标系

自动蒙版的 guide 图像和 SAM/SmartRegion 的 guide **不在同一坐标系**：

| guide 来源 | 坐标系 | 尺寸 | 用途 |
|------------|--------|------|------|
| 管线 `full_pipeline_renderer.dart` | **裁剪后输出空间** | ≤512px | 画笔 autoMask 颜色匹配 |
| SAM `segmentation_service.dart` | **全图空间** | ≤1024px | SAM embedding + 推理 |
| SmartRegion `smart_region_service.dart` | **全图空间** | ≤1280px | flood fill 种子色比较 |

**管管线 guide 是从裁剪后的 `current` 图像读取的**，所以画笔笔触坐标（输出空间）和 guide 是同一空间，可以直接比较颜色。

**SAM/SmartRegion guide 是全图空间**，所以 seed 坐标必须先变换。

**两者不要混淆。**

---

## 五、缓存失效规则

### BrushMaskCache

- **key**：`maskId`（字符串）
- LRU 容量 **8**
- **有效条件**：同一个 `mask` 引用 + 同输出尺寸 + (无 autoMask 或 `guideEpoch` 相同)
- **guideEpoch** = `Object.hash(devFp, params.crop)`
  - 其中 `devFp` 是 `_developFingerprint()` 返回的四元组 `(bodyHash, identityHashCode(sourceImage), targetWidth, targetHeight)`，不是单一哈希值
- **⚠️ crop 变更时**：guideEpoch 变化 → autoMask 重新光栅化；baseRaster 不失效（全图空间，inverseMap 实时映射）
- **⚠️ 删除 local adjustment 时**：必须调用 `brushCache.evict(maskId)`

### DevelopPassCache

- **key**：`(bodyHash, identityHashCode(sourceImage), targetWidth, targetHeight)`
- LRU 容量 3
- **⚠️ 裁剪变更时**：如果输出尺寸变化，缓存自动失效

### SAM Embedding 缓存

- **key**：`Object.hash(identityHashCode(src), paramsWithoutLocalsOrCrop, gw, gh)`
- **⚠️ 不包含 crop**，因为 guide 用 identity crop 渲染，crop 变更不影响 embedding

---

## 六、Isolate 边界

| 功能 | 运行位置 | 注意事项 |
|------|----------|----------|
| 管线渲染（develop/crop/mask/sharpen） | 主线程 | GPU shader，不做重计算 |
| applyCropTransform | 主线程 | Canvas 光栅化 |
| SAM 推理 | 主线程 | ONNX，可能阻塞 UI |
| SR 预览 | 主线程 | ONNX，部分 Android 设备 SIGILL |
| SR 导出 | 隔离 Isolate | 通过 SendPort 传 Uint8List |
| HDR 融合 | 隔离 Isolate | Float32 拉普拉斯金字塔 |
| JPEG 编码 | 隔离 Isolate | Isolate.run 一次性 |

**⚠️ 不要把 `ui.Image` 传入 Isolate（不可跨 isolate 传递）。必须先 `toByteData()` 转为 Uint8List。**

---

## 七、Shader Uniform 约束

| Shader | Uniform 数量 | 断言 |
|--------|-------------|------|
| develop | 55 | `develop_uniforms.dart` `assert(i == 55)` |
| mask | 24 | `full_pipeline_renderer.dart` `assert(i == 24)` |

**⚠️ 添加新 uniform 时必须更新对应断言数字，否则 Debug 模式崩溃。**

---

## 八、ONNX Runtime 依赖约束

- **`onnxruntime_v2` 版本必须锁定为 `1.23.0`**（不是 `^1.23.0`）
- `appendDefaultProviders()` 返回 `void`，不能用 `await`
- `flutter_onnxruntime` 不能与 `onnxruntime_v2` 共存

---

## 九、导出流程中的裁剪

```
exporter.dart
  → FullPipelineRenderer.render()  // 内含 applyCropTransform
  → SR（如果启用，在管线完整输出上 2x 放大）
  → 水印
  → 编码保存
```

导出和预览共用同一个 `FullPipelineRenderer.render()`，蒙版处理完全一致。
导出不传 developCache / brushCache，每次从头渲染。
裁剪在 `FullPipelineRenderer.render()` 内部完成（`applyCropTransform`），SR 作用于管线完整输出。

---

## 十、常见 BUG 模式与预防

### BUG 1：裁剪后蒙版错位

**根因**：baseRaster 存在裁剪后坐标系，裁剪变更后蒙版无法跟随。
**预防**：baseRaster 必须存全图坐标，光栅化时用 `inverseMap` 映射。

### BUG 2：SAM/SmartRegion 选中全图中错误位置

**根因**：seed 坐标（输出空间）直接用于全图 guide，未做空间变换。
**预防**：seed 必须经 `crop.outputToSourceOffset()` 变换。

### BUG 3：straighten 旋转后蒙版出现黑角伪影

**根因**：`inverseMap` 返回超出源图范围的坐标，未做越界检查。
**预防**：`_rasterizeCpu` 中必须有 `ix < 0 || ix >= srcW || iy < 0 || iy >= srcH` 检查。

### BUG 4：旋转方向不一致

**根因**：在 Canvas 上手算逆变换时旋转方向与正向变换不一致。
**预防**：蒙版预览不要手算 Canvas 变换，改用 `rasterizeBrushMask(crop: crop)` 生成输出空间的蒙版图，直接绘制。

### BUG 5：裁剪变更后缓存返回旧蒙版

**根因**：`guideEpoch` 未包含 crop hash，或 `BrushMaskCache` 未检查 epoch。
**预防**：`guideEpoch = Object.hash(devFp, params.crop)`。

### BUG 6：添加新 uniform 后 Debug 模式崩溃

**根因**：忘记更新 `assert(i == N)` 中的数字。
**预防**：改 uniform 数量时搜索所有 `assert(i ==` 并更新。

### BUG 7：Isolate 中传递 ui.Image

**根因**：`ui.Image` 不可跨 Isolate 传递。
**预防**：先 `toByteData()` 转为 `Uint8List`，Isolate 中重建。

---

## 十一、文件速查表

| 文件 | 核心职责 | 修改时联动 |
|------|----------|-----------|
| `crop_params.dart` | 裁剪数学（inverseMap、outputToSourceNorm） | `brush_rasterizer.dart`、`crop_transform.dart`、两个 service |
| `crop_transform.dart` | 正向裁剪（applyCropTransform） | `crop_params.dart`（逆变换必须一致）、`full_pipeline_renderer.dart` |
| `brush_rasterizer.dart` | 蒙版光栅化（GPU/CPU 两条路径） | `crop_params.dart`、`full_pipeline_renderer.dart`、`mask_cache.dart`、`local_mask_overlay.dart` |
| `mask_cache.dart` | 蒙版 LRU 缓存 | `brush_rasterizer.dart`、`full_pipeline_renderer.dart` |
| `full_pipeline_renderer.dart` | 渲染管线主流程 | 几乎所有 render/ 文件 |
| `homography.dart` | 透视变换矩阵缓存 | `full_pipeline_renderer.dart`（PerspectiveMatrixCache） |
| `render_engine.dart` | Develop shader 执行 | `develop_uniforms.dart`（uniform 数量） |
| `develop_uniforms.dart` | Develop uniform 布局（55 个） | shader 文件（.frag） |
| `segmentation_service.dart` | SAM 分割 | `crop_params.dart`（seed 变换）、`sam_session.dart` |
| `smart_region_service.dart` | 智能区域 | `crop_params.dart`（seed 变换）、`brush_rasterizer.dart`（refineMaskEdges） |
| `local_mask_overlay.dart` | 蒙版 UI 交互 + 预览 | `brush_rasterizer.dart`（rasterizeBrushMask）、`crop_params.dart`、两个 service |
| `local_mask_painter.dart` | 蒙版绘制（Canvas） | `mask_shape.dart`（坐标系） |
| `exporter.dart` | 导出流程 | `full_pipeline_renderer.dart`、`sr_service.dart` |
| `mask_shape.dart` | 蒙版数据模型 | 所有蒙版相关文件 |
| `local_adjustment.dart` | 局部调整模型 | `local_state.dart`、`full_pipeline_renderer.dart` |
