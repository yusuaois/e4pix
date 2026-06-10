# 水印边框 (Watermark Border) — 架构文档

## 1. 核心设计原则

### 1.1 统一几何模型 (WatermarkGeometry)

所有布局计算集中在 `lib/render/watermark_geometry.dart` 的 `WatermarkGeometry` 类：

```
输入: 图片宽高比 (imageAspectRatio) + WatermarkConfig
计算: 基于固定基准宽度 (kBaseWidth=1000px) 的绝对画布
输出: canvasSize, imageRect, infoRect, borderWidth, cornerRadius, ...
      + exportScale(fullResImageWidth) → 导出缩放因子
```

**Preview 和 Export 共用此模型**，保证数学骨架 100% 一致。

### 1.2 预览：FittedBox 锁死比例

`lib/widgets/preview/watermark_preview.dart`:

```
FittedBox(fit: BoxFit.contain)          // 窗口拉伸 → 仅整体缩放
  └─ SizedBox(width: geometry.canvasW, height: geometry.canvasH)
       └─ Stack(绝对坐标定位)
            ├─ Layer 0: 背景 (Positioned.fill)
            ├─ Layer 1: Logo+EXIF (geometry.infoRect)
            └─ Layer 2: 原图 (geometry.imageRect, 圆角+阴影)
```

- 预览不依赖 `LayoutBuilder` / `BoxFit.contain` 等响应式布局
- 内部排版永远固定，窗口大小变化仅触发 `FittedBox` 整体缩放

### 1.3 导出：纯 Canvas + 动态 scale

`lib/render/watermark_exporter.dart`:

```
scale = fullResImage.width × imageScale / geometry.imageRect.width

所有参数 × scale 后在 PictureRecorder + Canvas 上绘制:
  - 背景: 降采样→模糊(缩略图分辨率)→拉伸到导出画布
  - 原图: canvas.drawImageRect → 全分辨率渲染图
  - Logo: instantiateImageCodec 源文件重解码 → canvas.drawImageRect
  - 文本: ParagraphBuilder + fontSize × scale → 矢量锐利文字
  - 阴影: canvas.drawRRect + MaskFilter.blur
```

- 导出画布紧贴内容 (`canvasW = imageDisplayW + 2×borderW`)，左右边距自然对称
- 模糊背景与预览使用完全相同的两阶段策略（256px 缩略图→模糊→拉伸）

## 2. 文件清单

| 文件 | 职责 |
|------|------|
| `lib/render/watermark_geometry.dart` | 统一几何布局模型，Preview/Export 共用 |
| `lib/widgets/preview/watermark_preview.dart` | FittedBox + 绝对坐标预览组件 |
| `lib/render/watermark_exporter.dart` | 纯 Canvas 离屏导出，动态 scale 映射 |
| `lib/core/models/watermark_config.dart` | WatermarkConfig 不可变数据模型 + 枚举 |
| `lib/state/watermark/watermark_state.dart` | WatermarkNotifier + Provider |
| `lib/widgets/develop/sections/watermark_section.dart` | 侧边栏 UI 控件 |
| `lib/render/exporter.dart` | 导出管线入口，接入 WatermarkExporter.composite() |

## 3. 布局算法详解

### 3.1 参考画布计算

```
kBaseWidth = 1000                          // 固定基准宽度
borderW = config.borderWidth               // 边框宽度（逻辑像素）
availW = kBaseWidth - 2 × borderW          // 图片可用宽度
imageDisplayW = availW × imageScale        // 原图显示宽度
imageDisplayH = imageDisplayW / aspectRatio // 原图显示高度

infoH = logoMaxH + gap + textH + 2×textPad // 信息层高度
canvasW = imageDisplayW + 2 × borderW      // 画布宽度（紧贴内容）
canvasH = imageDisplayH + 2 × borderW + infoH // 画布高度

hMargin = borderW                          // 水平居中边距（左侧=右侧=borderW）
imageRect = (hMargin, y, imageDisplayW, imageDisplayH)
infoRect  = (hMargin, y_info, imageDisplayW, infoH)
```

### 3.2 导出 scale 映射

```
exportScale = fullResW × imageScale / imageDisplayW
            = fullResW / availW            // imageScale 因子抵消

exportCanvasW = canvasW × exportScale
exportCanvasH = canvasH × exportScale
exportHMargin = hMargin × exportScale     // 导出水平边距，左右对称
```

### 3.3 模糊背景算法

```
Step 1: 降采样到 256px 缩略图 (max edge)
Step 2: fillScale = max(refCanvasW/thumbW, refCanvasH/thumbH)
        compensatedBlur = blurRadius × downscale × fillScale
Step 3: saveLayer + ImageFilter.blur 在缩略图分辨率上施加模糊
Step 4: drawImageRect 拉伸到导出画布
```

与预览 `_BlurredBackgroundLayer` 使用完全相同的公式和流程。

## 4. 数据流

```
用户操作 slider/dropdown
  → WatermarkNotifier.update(cfg.copyWith(...))
    → watermarkConfigProvider 通知所有监听者
      → WatermarkPreview 重建 (WatermarkGeometry.compute → FittedBox)
      → 导出时 WatermarkExporter.composite(fullResImage, config, metadata)
```

## 5. 多语言

所有 UI 文字通过 `tr()` 函数国际化，翻译文件位于:
- `assets/translations/en-US.json`
- `assets/translations/zh-CN.json`

水印相关翻译键以 `watermark` 为前缀。
