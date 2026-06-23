# 超分辨率模块技术文档

## 1. 功能概述

在调色面板中新增 Super Resolution Section，基于 Real-ESRGAN ONNX 模型对图片执行 2x 超分辨率放大。包含三个使用场景：Section UI 控制、预览区局部预览、导出时全图超分。

## 2. 模型

- 模型文件：`assets/models/RealESRGAN_x2.onnx`（约 66MB）
- 输入格式：NCHW float32 `[1, 3, H, W]`，像素值归一化到 `[0, 1]`
- 输出格式：NCHW float32 `[1, 3, H*2, W*2]`
- 推理框架：`onnxruntime_v2`（FFI 直连，非 MethodChannel）

模型文件需从 Real-ESRGAN 仓库单独下载，放入 `assets/models/` 目录。后续扩展 3x/4x 只需更换模型文件，代码中 `srScale` 字段已预留。

## 3. 数据模型

`lib/core/models/adjustment_params.dart` 新增两个字段：

| 字段        | 类型   | 默认值  | 说明                 |
| ----------- | ------ | ------- | -------------------- |
| `srEnabled` | `bool` | `false` | 超分辨率总开关       |
| `srScale`   | `int`  | `2`     | 放大倍数，目前固定 2 |

这两个字段参与 `copyWith`、`==`、`hashCode`、`toJson`、`fromJson`。XMP sidecar 中同步序列化。

## 4. 推理服务

文件：`lib/services/sr/sr_service.dart`

`SrService` 是全局单例，职责分为两部分：

### 4.1 预览推理（主线程）

`upscaleRegion(rgbaBytes, width, height)` — 接收 128×128 的 RGBA 像素，返回 256×256 的 `ui.Image`。

调用链：`_rgbaToNchw` → `OrtValueTensor.createTensorWithDataList` → `session.run` → 读取输出 → `_nchwToRgba` → `decodeImageFromPixels`。

主线程 session 通过 `appendDefaultProviders()` 创建，自动选择可用硬件。

### 4.2 导出推理（后台 Isolate）

`upscaleFull(source, onProgress)` — 对全图执行分块超分。

执行流程：

1. 主线程：获取源图 RGBA 像素（`toByteData`）
2. 主线程：通过 `Isolate.spawn` 启动后台 Isolate，传入模型字节 + 源图像素
3. Isolate 内部：创建独立 session → 分块推理 → 通过 `SendPort` 返回结果
4. 主线程：将结果字节转为 `ui.Image`

Isolate 内部的 session 也尝试 `appendDefaultProviders()`，逐个 fallback 到 CPU。

### 4.3 取消机制

`cancelExport()` 方法调用 `Isolate.kill(priority: Isolate.immediate)` 立即终止后台 Isolate。

导出管线中，exporter 每 500ms 轮询 `isCancelled` 回调。一旦用户取消，立即调用 `cancelExport()` 杀掉 Isolate，然后抛出 `ExportCancelledException`。

### 4.4 分块策略

| 参数      | 值       | 说明                               |
| --------- | -------- | ---------------------------------- |
| tile 大小 | 128×128  | 模型输入尺寸                       |
| 重叠      | 8px      | 避免拼接接缝                       |
| 混合权重  | 线性衰减 | 边缘像素权重随距边缘距离线性下降   |
| 归一化    | 后处理   | 所有 tile 处理完后统一除以累积权重 |

以 7968×5320 的图片为例：36×54 = 1944 个 tile，每个约 400ms，总计约 13 分钟。

## 5. UI 组件

### 5.1 SrSection

文件：`lib/widgets/develop/sections/sr_section.dart`

`ConsumerStatefulWidget`，风格与 Watermark Section 一致：

```
SectionLabel: "Super Resolution"
├── _SwitchTile: "启用超分辨率" + Switch
└── [开启后显示]
    ├── 放大倍数: 2x（只读）
    ├── _SwitchTile: "预览效果" + Switch
    └── 模型状态: ✓ 已加载 / 加载中... / 未加载
```

总开关开启时自动调用 `_loadModel()`，无需用户手动触发。模型加载状态通过 `SrService.instance.ensureLoaded()` 获取。

### 5.2 SrPreviewOverlay

文件：`lib/widgets/preview/sr_preview_overlay.dart`

`ConsumerStatefulWidget`，叠加在预览区右下角。

交互：

- 首次显示时自动推理源图中心区域
- 点击小窗任意位置 → 切换到该位置对应的源图区域执行超分
- 小窗大小根据预览区宽度自适应缩放（`displaySize.width / 600`，范围 0.4-1.0）

源图像素在首次推理时提取并缓存（`_cachedBytes`），切图时清除缓存。使用 `RawImage` 显示超分结果。

### 5.3 面板集成

| 面板                               | 改动                                                        |
| ---------------------------------- | ----------------------------------------------------------- |
| `vertical_adjustment_panel.dart`   | Tab 数 10→11，新增 `Tab(text: tr('superResolution'))`       |
| `horizontal_adjustment_panel.dart` | `_ToolRail` 新增 `Icons.auto_awesome` 图标                  |
| `develop_tool_state.dart`          | `DevelopTool` 枚举新增 `sr`                                 |
| `develop_sections.dart`            | 新增 `export 'sections/sr_section.dart'`                    |
| `preview_area.dart`                | `_withSrOverlay` 方法在预览 Stack 上叠加 `SrPreviewOverlay` |

### 5.4 状态管理

| Provider                   | 类型                    | 文件                                 | 说明         |
| -------------------------- | ----------------------- | ------------------------------------ | ------------ |
| `srPreviewEnabledProvider` | `StateProvider<bool>`   | `state/tools/sr_state.dart`          | 预览小窗开关 |
| `srEnabled` / `srScale`    | `AdjustmentParams` 字段 | `core/models/adjustment_params.dart` | 超分参数     |

## 6. 导出集成

`lib/render/exporter.dart` 中，SR 位于 FullPipelineRenderer.render() 之后、水印合成之前：

```
解码 → _checkCancel → 渲染 → _checkCancel → SR(Isolate) → _checkCancel → 水印 → _checkCancel → 编码
```

SR 步骤的特殊处理：

- `upscaleFull` 返回的 `Future` 通过 `.then()` 挂起，不阻塞 exporter
- exporter 每 500ms 轮询 `isCancelled`
- 取消时调用 `SrService.instance.cancelExport()` 杀掉 Isolate
- SR 失败时 catch 异常，跳过 SR 继续导出原图

## 7. 已知限制

- GPU 加速：`onnxruntime_v2` 自带的 DLL 为 CPU-only 版本，需要手动替换 GPU 版 DLL 才能启用 CUDA/DirectML
- DirectML 兼容性：RealESRGAN 的 Resize 节点在 DirectML 下可能报错（`E_INVALIDARG`），CUDA 兼容性更好
- 预览小窗与主预览共享源图 GPU 纹理时，Flutter 引擎会打印 `GrBackendTextureImageGenerator` 警告，无功能影响

## 8. 文件清单

| 文件                                                   | 职责                                         |
| ------------------------------------------------------ | -------------------------------------------- |
| `lib/services/sr/sr_service.dart`                      | 推理服务（主线程预览 + Isolate 导出 + 取消） |
| `lib/widgets/develop/sections/sr_section.dart`         | Section UI                                   |
| `lib/widgets/preview/sr_preview_overlay.dart`          | 预览区覆盖层                                 |
| `lib/state/tools/sr_state.dart`                        | `srPreviewEnabledProvider`                   |
| `lib/core/models/adjustment_params.dart`               | `srEnabled` / `srScale` 字段                 |
| `lib/state/tools/develop_tool_state.dart`              | `DevelopTool.sr` 枚举                        |
| `lib/render/exporter.dart`                             | 导出管线 SR 集成 + 取消轮询                  |
| `lib/widgets/preview/preview_area.dart`                | `_withSrOverlay` 叠加逻辑                    |
| `lib/widgets/develop/vertical_adjustment_panel.dart`   | 竖屏面板 SR tab                              |
| `lib/widgets/develop/horizontal_adjustment_panel.dart` | 横屏面板 SR rail                             |
| `assets/models/RealESRGAN_x2.onnx`                     | 模型文件                                     |
| `assets/translations/en-US.json`                       | 英文翻译（`superRes*` 前缀）                 |
| `assets/translations/zh-CN.json`                       | 中文翻译                                     |
