# 水印边框模块技术文档

## 1. 功能概述

在导出图片时可选添加水印边框，包含背景层、原图层、Logo 层和 EXIF 信息层。预览和导出共用同一套几何布局模型，保证视觉一致性。

## 2. 核心设计

### 2.1 统一几何模型

所有布局计算集中在 `lib/render/watermark_geometry.dart` 的 `WatermarkGeometry` 类。

输入：图片宽高比 + `WatermarkConfig`
基准：固定参考宽度 `kBaseWidth = 1000px`

计算流程：

```
borderW = config.borderWidth
availW = kBaseWidth - 2 × borderW
imageDisplayW = availW × imageScale
imageDisplayH = imageDisplayW / aspectRatio
infoH = logoMaxH + gap + textH + 2 × textPad
canvasW = imageDisplayW + 2 × borderW
canvasH = imageDisplayH + 2 × borderW + infoH
hMargin = borderW
imageRect = (hMargin, y, imageDisplayW, imageDisplayH)
infoRect = (hMargin, y_info, imageDisplayW, infoH)
```

Preview 和 Export 共用此模型，数学骨架完全一致。

### 2.2 预览渲染

`lib/widgets/preview/watermark_preview.dart`

使用 `FittedBox(fit: BoxFit.contain)` 包裹固定尺寸的 `SizedBox`，内部用 `Stack` + 绝对坐标定位各层：

```
FittedBox
└─ SizedBox(canvasW × canvasH)
   └─ Stack
      ├─ Layer 0: 背景 (Positioned.fill)
      ├─ Layer 1: Logo + EXIF (infoRect)
      └─ Layer 2: 原图 (imageRect, 圆角 + 阴影)
```

预览不依赖 `LayoutBuilder`，内部排版固定，窗口大小变化仅触发 `FittedBox` 整体缩放。

### 2.3 导出渲染

`lib/render/watermark_exporter.dart`

导出时根据原图分辨率计算缩放因子：

```
exportScale = fullResW × imageScale / imageDisplayW
            = fullResW / availW
```

所有坐标和尺寸乘以 `exportScale` 后，在 `PictureRecorder` + `Canvas` 上离屏绘制：

- 背景：降采样到 256px 缩略图 → `ImageFilter.blur` 模糊 → 拉伸到导出画布
- 原图：`canvas.drawImageRect` 渲染全分辨率图
- Logo：`instantiateImageCodec` 从源文件重解码 → `canvas.drawImageRect`
- 文本：`ParagraphBuilder` + `fontSize × scale` → 矢量锐利文字
- 阴影：`canvas.drawRRect` + `MaskFilter.blur`

## 3. 数据模型

`lib/core/models/watermark_config.dart`

`WatermarkConfig` 是不可变数据类，包含以下主要字段：

| 字段                | 类型                | 说明                                     |
| ------------------- | ------------------- | ---------------------------------------- |
| `enabled`           | `bool`              | 总开关                                   |
| `backgroundType`    | `BackgroundType`    | 背景类型（模糊原图 / 纯色 / 自定义图片） |
| `backgroundColor`   | `Color`             | 纯色背景颜色                             |
| `backgroundBlur`    | `double`            | 模糊半径                                 |
| `borderWidth`       | `double`            | 边框宽度                                 |
| `borderColor`       | `Color`             | 边框颜色                                 |
| `cornerRadius`      | `double`            | 原图圆角                                 |
| `imageScale`        | `double`            | 原图在画布中的缩放比例                   |
| `infoPlacement`     | `InfoPlacement`     | 信息层位置（上方 / 下方 / 四角叠加）     |
| `logoSource`        | `LogoSource`        | Logo 来源（内置 / 自定义）               |
| `logoAssetPath`     | `String`            | 内置 Logo 路径                           |
| `logoCustomPath`    | `String`            | 自定义 Logo 路径                         |
| `logoScale`         | `double`            | Logo 缩放                                |
| `exifMode`          | `ExifMode`          | EXIF 来源（自动提取 / 自定义文本）       |
| `enabledExifFields` | `Set<ExifField>`    | 启用的 EXIF 字段                         |
| `customText`        | `String`            | 自定义文本                               |
| `canvasAspectRatio` | `CanvasAspectRatio` | 画布宽高比                               |

`InfoPlacement`、`ExifField`、`LogoSource`、`CanvasAspectRatio` 均为枚举，定义在同一文件中。

## 4. 状态管理

`lib/state/watermark/watermark_state.dart`

`WatermarkNotifier` 继承 `Notifier<WatermarkConfig>`，提供 `update(WatermarkConfig)` 方法。

通过 `watermarkConfigProvider` 暴露给 UI 层，所有 UI 控件通过 `ref.watch` 监听并重建。

## 5. UI 控件

`lib/widgets/develop/sections/watermark_section.dart`

Section 结构：

```
SectionLabel: "Watermark"
├── _SwitchTile: "启用水印边框" + Switch
├── [未启用时] 提示文本
└── [启用后]
    ├── 背景类型下拉选择
    ├── 颜色选择器 / 模糊半径滑块
    ├── 边框宽度 / 颜色
    ├── 原图缩放 / 圆角
    ├── 信息层位置
    ├── Logo 来源 + 选择
    ├── EXIF 模式 + 字段勾选
    └── 文本颜色 / 字号
```

所有控件通过 `cfg.copyWith(...)` 更新 `WatermarkConfig`，经 `WatermarkNotifier.update()` 写入状态。

## 6. 导出集成

`lib/render/exporter.dart`

水印合成位于 SR 之后、编码之前：

```dart
if (watermarkConfig != null && watermarkConfig.enabled) {
  final composited = await WatermarkExporter.composite(
    fullResImage: output,
    config: watermarkConfig,
    metadata: metadata,
  );
  output.dispose();
  finalOutput = composited;
}
```

`WatermarkExporter.composite()` 内部调用 `WatermarkGeometry.compute()` 获取布局参数，然后按 `exportScale` 缩放在 Canvas 上绘制。

## 7. 多语言

所有 UI 文字通过 `tr()` 国际化，翻译键以 `watermark` 为前缀。`InfoPlacement` 和 `ExifField` 的 `displayLabel` 使用翻译 key（如 `watermarkPlacementAbove`、`watermarkExifCamera`），UI 层调用 `.tr()`。

## 8. 文件清单

| 文件                                                  | 职责                                             |
| ----------------------------------------------------- | ------------------------------------------------ |
| `lib/render/watermark_geometry.dart`                  | 统一几何布局模型，Preview/Export 共用            |
| `lib/widgets/preview/watermark_preview.dart`          | FittedBox + 绝对坐标预览组件                     |
| `lib/render/watermark_exporter.dart`                  | 纯 Canvas 离屏导出，动态 scale 映射              |
| `lib/core/models/watermark_config.dart`               | WatermarkConfig 不可变数据模型 + 枚举            |
| `lib/state/watermark/watermark_state.dart`            | WatermarkNotifier + Provider                     |
| `lib/widgets/develop/sections/watermark_section.dart` | 侧边栏 UI 控件                                   |
| `lib/render/exporter.dart`                            | 导出管线入口，接入 WatermarkExporter.composite() |
