# 水印边框 (Watermark Border) — 技术实现方案

## 1. 项目架构分析摘要

### 1.1 状态管理层
- `AdjustmentParams`：不可变模型，所有调色参数聚合体，通过 `copyWith` 更新
- `currentParamsNotifierProvider`：核心 Notifier，管理当前照片参数
- `isUserDraggingSliderProvider`：拖动 Slider 时降级渲染的全局信号
- `LutState`/`LutNotifier`：LUT 纹理的异步加载与缓存
- `DecodedImageState`：持有 `ui.Image` + `RawMetadata`（含 EXIF）

### 1.2 UI 层
- `DevelopTool` 枚举 + `_RailItem`（46×46 图标按钮）构成右侧工具栏
- `HorizontalAdjustmentPanel`（桌面） / `VerticalAdjustmentPanel`（手机）
- 每个子 Section 使用 `SectionLabel` + `DevelopSliderTile` 的模式
- `TrackedSlider`：包裹系统 Slider + 自动联动 `isUserDraggingSliderProvider`

### 1.3 渲染管线
```
RAW 解码 → PreviewRenderer (CustomPaint + GLSL) → 显示
            └─ MultiPassPreview（离屏多 pass：develop → crop → mask → sharpen）
               └─ FullPipelineRenderer.render()
```

### 1.4 导出管线
```
Exporter.exportFullRes() → FullPipelineRenderer.render() → JPEG/PNG 编码 → 写入文件
```

---

## 2. WatermarkConfig — 纯数据 State 设计

### 2.1 创建独立的 `WatermarkConfig` 模型（`lib/core/models/watermark_config.dart`）

```dart
@immutable
class WatermarkConfig {
  // 开关
  final bool enabled;

  // 布局
  final double blurRadius;        // 0 ~ 100 px
  final double borderWidth;       // 20 ~ 200 px
  final double imageScale;        // 0.0 ~ 1.0 (原图缩放比例)

  // 质感
  final double cornerRadius;      // 0 ~ 100 px
  final double shadowIntensity;   // 0.0 ~ 1.0

  // 背景
  final BackgroundType backgroundType; // solidColor | image | blurredOriginal
  final Color backgroundColor;

  // Logo
  final String? logoBrand;        // null = none, "sony", "nikon" 等
  final double logoSize;          // 0 ~ 1 (relative)
  final double logoOpacity;       // 0 ~ 1

  // 文本
  final bool showExif;            // 是否显示 EXIF 信息
  final String? fontFamily;       // 字体名称
  final double fontSize;          // 文字大小
  final FontWeight fontWeight;
  final double textOpacity;       // 0 ~ 1
  final double textPadding;       // 内容边距
  final WatermarkColorMode colorMode; // light | dark
  final InfoPlacement infoPlacement;  // above | below（在原图上方/下方）

  const WatermarkConfig({...});
  factory WatermarkConfig.defaults = ...;
  WatermarkConfig copyWith({...});
}

enum BackgroundType { solidColor, image, blurredOriginal }
enum WatermarkColorMode { light, dark }
enum InfoPlacement { above, below }
```

### 2.2 Riverpod Notifier（`lib/state/watermark/watermark_state.dart`）

```dart
class WatermarkNotifier extends Notifier<WatermarkConfig> {
  @override
  WatermarkConfig build() => WatermarkConfig.defaults;

  void update(WatermarkConfig config) => state = config;
  void toggle() => state = state.copyWith(enabled: !state.enabled);
  void reset() => state = WatermarkConfig.defaults;
}

final watermarkConfigProvider = NotifierProvider<WatermarkNotifier, WatermarkConfig>(
  WatermarkNotifier.new,
);
```

### 2.3 为什么独立于 `AdjustmentParams`？
- 水印边框是**展示/导出**层面的功能，不应污染调色参数模型
- `AdjustmentParams` 聚焦色彩/裁切/局部调整，已十分庞大
- 独立 State 使导出逻辑更清晰：`WatermarkConfig` + 渲染结果 → 水印合成
- 便于未来扩展（如模板保存/加载）

---

## 3. Preview Area 渲染层方案

### 3.1 核心思路：Flutter Widget Stack 而非 Shader

水印边框的**三层嵌套布局**天然适合 Flutter 的 `Stack` widget：

```
┌─────────────────────────────────────┐
│ 第 0 层：背景                        │
│   ├─ 纯色：Container(color)         │
│   ├─ 图片：RawImage                 │
│   └─ 模糊原图：BackdropFilter +      │
│       降采样缩略图                   │
├─────────────────────────────────────┤
│ 第 1 层：Logo + EXIF                │
│   ├─ RawImage(logo.webp)           │
│   └─ Text(EXIF)                    │
├─────────────────────────────────────┤
│ 第 2 层：清晰原图（居中）            │
│   └─ 现有的 PreviewRenderer /       │
│       MultiPassPreview              │
└─────────────────────────────────────┘
```

### 3.2 性能优化：背景模糊的降采样策略

**问题**：`ImageFilter.blur` 在高分辨率下极为耗时，拖动 Slider 时可能导致严重掉帧。

**解决方案**：三级质量策略
1. **拖动中**：后台 64×64 缩略图进行模糊 → 低质量但流畅（60fps）
2. **静止**：256×256 缩略图模糊 → 高质量预览
3. **导出**：全分辨率离屏渲染

```dart
// 背景层 Widget
class WatermarkBlurredBackground extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDragging = ref.watch(isUserDraggingSliderProvider);
    final config = ref.watch(watermarkConfigProvider);

    // 根据拖动状态选择缩略图尺寸
    final thumbSize = isDragging ? 64.0 : 256.0;

    // 关键：使用 RepaintBoundary 隔离模糊区域
    return RepaintBoundary(
      child: ClipRRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: config.blurRadius * (thumbSize / sourceSize),
            sigmaY: config.blurRadius * (thumbSize / sourceSize),
          ),
          child: RawImage(/* 缩略图 */),
        ),
      ),
    );
  }
}
```

### 3.3 三层渲染树的 RepaintBoundary 策略

```
RepaintBoundary #root (整个水印预览)
├─ RepaintBoundary #layer0 (背景层 — 参数不变时不重绘)
├─ RepaintBoundary #layer1 (Info 层 — 仅水印参数变化时重绘)
└─ RepaintBoundary #layer2 (原图层 — 调色参数变化时重绘)
     └─ PreviewRenderer / MultiPassPreview (现有逻辑)
```

核心原则：
- 调色参数变化 → 仅重绘 layer0（若为模糊原图）+ layer2
- 水印参数变化 → 仅重绘 layer0 + layer1
- `RepaintBoundary` 隔离各层，避免相互触发不必要的重绘

### 3.4 预览模式切换

在 `PreviewArea._buildBody()` 中增加分支：

```dart
Widget _buildBody(...) {
  final watermarkEnabled = ref.watch(
    watermarkConfigProvider.select((c) => c.enabled)
  );

  if (watermarkEnabled) {
    return _buildWatermarkPreview(state, params, lut, lutEnabled, ref);
  }

  // ... existing logic
}
```

---

## 4. 离屏高清导出方案（防 OOM）

### 4.1 核心风险
RAW 原图通常 6000×4000 = 24MP。直接构建此尺寸的 Flutter Widget Tree 进行截图，在移动端（尤其是 4-6GB RAM 的 Android 中端机）极易 OOM。

### 4.2 方案：基于 `PictureRecorder` 的分步合成

不是一次性构建全分辨率 Widget Tree，而是：

```
Step 1: 用现有 Exporter 获取调色渲染结果 (ui.Image, 全分辨率)
Step 2: 确定导出画布尺寸
Step 3: 用 PictureRecorder + Canvas 直接在 Canvas 上绘制：
  a. drawImageRect (背景层 — 模糊/纯色)
  b. drawParagraph (EXIF 文本)
  c. drawImage (Logo，从 assets 加载为 ui.Image)
  d. drawImageRect (调色后的原图，居中缩放)
  e. drawRRect (圆角裁剪 + 阴影)
Step 4: picture.toImage() → PNG/JPEG 编码

全程在 Canvas 上操作，不构建 Widget Tree，内存可控
```

### 4.3 关键细节：全分辨率模糊
- 导出时背景模糊用 `Canvas.saveLayer` + `ImageFilter.blur`，或直接在 PictureRecorder 层面使用降采样模糊
- 全分辨率模糊极其昂贵 → 先缩小背景图到 1/N 尺寸做模糊，再拉伸回去（高斯模糊的性质允许这样做）
- 导出上限：对于 >24MP 的图，导出画布限制在 maxEdge ≤ 8000px，防止 OOM

### 4.4 导出函数接口设计

```dart
class WatermarkExporter {
  /// 导出带水印边框的全分辨率图片
  static Future<Uint8List> export({
    required ui.Image renderedImage,    // FullPipelineRenderer 的结果
    required WatermarkConfig config,
    required RawMetadata? metadata,     // EXIF
    required ExportFormat format,
    required int jpegQuality,
  });
}
```

在 `Exporter.exportFullRes()` 的最后阶段（FullPipelineRenderer.render() 之后），增加水印合成步骤。

---

## 5. 文件清单与任务分解

### Step 2（状态层）— 新增文件
| 文件 | 说明 |
|------|------|
| `lib/core/models/watermark_config.dart` | `WatermarkConfig` 不可变模型 + 枚举 |
| `lib/state/watermark/watermark_state.dart` | `WatermarkNotifier` + Provider |

### Step 3（UI 侧边栏）— 新增文件
| 文件 | 说明 |
|------|------|
| `lib/widgets/develop/sections/watermark_section.dart` | 水印边框 UI（Slider / Dropdown 等） |

### Step 3（UI 侧边栏）— 需修改文件
| 文件 | 修改内容 |
|------|----------|
| `lib/state/tools/develop_tool_state.dart` | 在 `DevelopTool` 枚举添加 `watermark` |
| `lib/widgets/develop/horizontal_adjustment_panel.dart` | `_ToolRail` 增加水印 `_RailItem` |
| `lib/widgets/develop/vertical_adjustment_panel.dart` | Tab 页增加水印 Section |
| `lib/widgets/develop/develop_sections.dart` | export watermark_section |

### Step 4（渲染层）— 新增文件
| 文件 | 说明 |
|------|------|
| `lib/widgets/preview/watermark_preview.dart` | 三层 Stack 预览组件 |
| `lib/render/watermark_exporter.dart` | 离屏 Canvas 导出 |

### Step 4（渲染层）— 需修改文件
| 文件 | 修改内容 |
|------|----------|
| `lib/widgets/preview/preview_area.dart` | `_buildBody()` 增加水印预览分支 |
| `lib/render/exporter.dart` | 导出流程末端接入水印合成 |
| `lib/state/providers.dart` | export watermark_state |
| `lib/widgets/export/export_dialog.dart` | 导出对话框增加水印开关（可选） |

---

## 6. 关于第 1 层中 "原图坐标上方/下方" 的语义

用户描述的第 1 层放在"原图坐标上方或下方"——这里 `InfoPlacement` 枚举的 above/below 含义是：
- **above**：Logo + EXIF 显示在第 2 层（清晰原图）的**上方**，即边框区域
- **below**：Logo + EXIF 显示在第 2 层的**下方**，即边框区域

信息层永远在边框区域内（第 0 层之上、第 2 层之外），不会遮挡清晰原图。

---

## 7. 后续步骤确认

以上为完整技术方案。请确认以下关键设计决策：

1. **`WatermarkConfig` 独立于 `AdjustmentParams`**：✓ 推荐
2. **预览使用 Flutter Widget Stack（而非 Shader）**：这是性能最优方案，因为：
   - 第 2 层原图直接复用现有 `PreviewRenderer`/`MultiPassPreview`，零额外成本
   - 第 0 层模糊用降采样缩略图 + `RepaintBoundary` 隔离
   - 圆角、阴影利用 Flutter 原生 `BoxDecoration`
3. **导出使用 Canvas 分步绘制（非 Widget 截图）**：内存安全，适合移动端
4. **Logo 资源已在 `assets/borders/logos/` 就位**：light/dark 各 14 个品牌

请确认方案，我将开始 Step 2 的实现。
