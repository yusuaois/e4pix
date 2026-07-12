# 如何新增画笔 — 开发者指南

> 当前已提取公共工具层（坐标变换、路径采样、纹理生命周期）、A/B 两类 Overlay 基类委托模式，和 BrushManifest 单点注册机制。
> 新增画笔只需创建 **6 个自包含文件** + 在 **4 个注册点** 添加少量胶水代码。
> B 类（原地修改）overlay 继承 `BaseEffectOverlayState`，~40 行即可。
>
> 以污点修复（`spot_heal`）为 B 类最简模板，加深减淡（`dodge_burn`）为 B 类复杂模板。

---

## 1. 架构概览

```
lib/brushes/
├── shared/
│   ├── stamp/                     # A 类（源-目标型）基类
│   │   ├── base_stamp_overlay.dart
│   │   ├── base_stamp_painter.dart
│   │   ├── stamp_compositor.dart
│   │   ├── stamp_gesture_handler.dart
│   │   ├── stamp_mark.dart
│   │   ├── stamp_painter_utils.dart
│   │   ├── persisted_stamp_state.dart
│   │   └── spot_data_texture.dart
│   ├── effect/                    # B 类（原地修改型）基类
│   │   ├── base_effect_overlay.dart
│   │   ├── base_effect_painter.dart
│   │   └── effect_gesture_handler.dart
│   ├── brush_hashes.dart          # 所有画笔的 hash 函数
│   ├── brush_layer_mixin.dart     # ShaderCacheMixin
│   ├── brush_warmup_utils.dart    # GPU 预热工具
│   └── brush_deactivate.dart      # 画笔退出调度
├── brush_manifest.dart            # 单点注册
├── clone_stamp/                   # A 类示例
├── healing/                       # A 类示例
├── history_brush/                 # A 类示例
├── spot_heal/                     # B 类示例（最简模板）
├── dodge_burn/                    # B 类示例
└── sponge/                        # B 类示例

<my_brush>/
├── my_brush_model.dart    # 数据模型：Mark 类 + 工具级枚举
├── my_brush_state.dart    # 状态管理：Notifier<MyBrushState>
├── my_brush_layer.dart    # Compose 图层：实现 BrushLayerProvider
├── my_brush_overlay.dart  # 手势交互：继承 BaseEffectOverlayState（B 类）或 BaseStampOverlayState（A 类）
├── my_brush_section.dart  # UI 面板：SectionLabel + PillChip + DevelopSliderTile
└── my_brush.frag          # Fragment Shader（放 assets/shaders/brushes/，pubspec.yaml shaders: 段注册）
```

### 1.1 两类画笔原型

| | 原型 A：源-目标转移 | 原型 B：原地修改 |
|---|---|---|
| 示例 | 图章、修复画笔、历史画笔 | 污点修复、加深减淡、海绵 |
| 是否需要 Alt+取样 | 是 | **否** |
| 是否有 clone source | 是 | **否** |
| committed preview 生命周期 | 有（hash 匹配） | **无** |
| 渲染方式 | 逐 mark shader pass | mask 光栅化 + 单 pass |
| Overlay 基类 | **`BaseStampOverlayState`** | **`BaseEffectOverlayState`** |
| Gesture Handler | **`StampGestureHandler`** | **`EffectGestureHandler`** |
| Painter 基类 | **`BaseStampPainter`** | **`BaseEffectPainter`** |
| 参考模板 | `clone_stamp/`、`healing/` | **`spot_heal/`（最简）** |

**建议**：如果是原地修改型（涂抹即生效），选择原型 B，从 `spot_heal/` 复制起步，overlay 只需 ~40 行（继承 `BaseEffectOverlayState`）。

---

## 2. Step-by-Step

### Step 1：数据模型（`my_brush_model.dart`）

创建 `@immutable` mark 类，至少包含：

```dart
@immutable
class MyBrushMark {
  final Offset target;    // 归一化源图坐标 [0..1]
  final double radius;    // 归一化半径
  final double hardness;  // 0..1，1=硬边
  // 按需添加画笔特有参数（如 mode、opacity、flow）

  const MyBrushMark({...});

  // 必须实现：copyWith、==、hashCode、toJson、fromJson
}
```

需要的枚举也在此定义。

**参考**：`spot_heal_model.dart`（最简，3 字段）、`dodge_burn_model.dart`（复杂，6 字段 + 2 枚举）

---

### Step 2：状态管理（`my_brush_state.dart`）

```dart
enum MyBrushMode { inactive, active }          // 必须：激活/停用模式

@immutable
class MyBrushState {                            // 交互状态
  final MyBrushMode mode;
  final double brushRadius;                     // 显示值（×1000）
  final double brushHardness;                   // 0..1
  // 按需添加：opacity、color、mode 选择器等
}

class MyBrushNotifier extends Notifier<MyBrushState> {
  @override MyBrushState build() => const MyBrushState();

  double get radiusNorm => state.brushRadius / 1000.0;

  // 必须实现的核心方法：
  //   addMarkAt(Offset target, double radiusNorm, double hardness)
  //   addStrokesBatch(List<Offset> targets, double radiusNorm, double hardness)
  //   removeMark(int index)
  //   clearAll()
  //
  // 这些方法内部通过 ref.read(currentParamsNotifierProvider) 修改
  // AdjustmentParams 中你的 marks list
}

final myBrushStateProvider =
    NotifierProvider<MyBrushNotifier, MyBrushState>(MyBrushNotifier.new);
```

**关键模式**：`addMarkAt` 和 `addStrokesBatch` 通过 `ref.read(currentParamsNotifierProvider.notifier).update(...)` 写入 marks，管道自动检测变化并重渲染。

**参考**：`spot_heal_state.dart`（~100 行，最简模板）

---

### Step 3：Overlay Widget（`my_brush_overlay.dart`）

**原型 B（推荐：继承 `BaseEffectOverlayState`，~40 行）**：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/crop_params.dart';
import '../../state/providers.dart';
import '../shared/effect/base_effect_overlay.dart';

class MyBrushOverlay extends ConsumerStatefulWidget { /* ... same as before ... */ }

class _MyBrushOverlayState extends BaseEffectOverlayState<MyBrushOverlay> {
  // ── Widget properties ──
  @override Size get imageDisplaySize => widget.imageDisplaySize;
  @override CropParams get crop => widget.crop;
  @override int get sourceWidth => widget.sourceWidth;
  @override int get sourceHeight => widget.sourceHeight;

  // ── Brush configuration ──
  @override double get brushNorm => ref.read(myBrushStateProvider).brushRadius / 1000.0;
  @override double get hardness => ref.read(myBrushStateProvider).brushHardness;
  @override Color get cursorColor => const Color(0xFFFFFFFF);
  @override bool get isActive => ref.watch(myBrushStateProvider).mode == MyBrushMode.active;

  // ── Callbacks ──
  @override
  void onAddMarkAt(Offset target, double radius, double hardness) {
    ref.read(myBrushStateProvider.notifier).addMarkAt(target, radius, hardness);
  }
  @override
  void onAddStrokesBatch(List<Offset> targets, double radius, double hardness) {
    ref.read(myBrushStateProvider.notifier).addStrokesBatch(targets, radius, hardness);
  }
}
```

基类已自动处理：光标 hover/exit、`MouseRegion` + `GestureDetector`、`PathBrushTracker` 笔画采样、`CustomPaint`（笔画路径 + 单点圆 + 光标环）。

**原型 A（继承 `BaseStampOverlayState`）**：参考 `clone_stamp_overlay.dart`（~200 行）。需额外提供 shader key、clone source、sampling、compositor 相关配置。

复用工具层（无需手写）：

| 工具 | 导入 | 用途 |
|------|------|------|
| `screenToSourceNorm` | `brush_coord_utils.dart` | 屏幕点击 → 源图归一化坐标 |
| `sourceToScreenNorm` | `brush_coord_utils.dart` | 源图坐标 → 屏幕位置（光标绘制） |
| `sourceRadiusToScreen` | `brush_coord_utils.dart` | 源图半径 → 屏幕半径 |
| `PathBrushTracker` | `path_brush_tracker.dart` | 路径均匀采样 |
| `computeOOBRects` | `brush_preview_utils.dart` | OOB 采样预览（仅原型 A） |

---

### Step 4：Shader 编写（`my_brush.frag`）

在 `assets/shaders/brushes/` 中创建 GLSL Fragment Shader，并在 `pubspec.yaml` 的 `shaders:` 段中注册。

```glsl
#version 460 core
// ... uniforms, samplers, main() ...
```

- Shader 注释用英文
- OOB 检查加 epsilon（±0.001）
- 硬度 ≥0.999 时用 step 替代 smoothstep
- **Uniform 数量对齐**：若实际用 5 个 float，传 6 个（第 6 个传 0.0）

**参考**：`spot_heal.frag`（IDW 填充）、`dodge_burn.frag`（Screen/Multiply 混合）

---

### Step 5：Layer Provider（`my_brush_layer.dart`）

实现 `BrushLayerProvider` 接口，接入 Compose 图层系统。

```dart
class MyBrushLayerProvider with ShaderCacheMixin implements BrushLayerProvider {
  @override String get id => 'my_brush';

  final _cache = IncrementalRenderCache<MyBrushMark>(
    computeKey: hashMyBrushMarks,
  );
  @override final ui.FragmentProgram brushProgram;

  MyBrushLayerProvider({required ui.FragmentProgram program})
    : brushProgram = program;

  @override bool isActive(AdjustmentParams p) => p.myBrushMarks.isNotEmpty;

  @override int computeMarksHash(AdjustmentParams p) =>
      hashMyBrushMarks(p.myBrushMarks);

  @override Future<BrushLayer> render({...}) async {
    // 1. 检查 marks 是否为空
    // 2. L1 cache 检查：_cache.getFromMarksCache(developKey, marks)
    // 3. 渲染：mask 光栅化或逐 mark shader pass
    // 4. 更新 cache：_cache.putMarksCache(developKey, marks, result)
    // 5. 返回 BrushLayer(id: id, texture: result, active: true)
  }

  @override Future<void> warmup(...) async { ... }  // 用 createEmptyMask()
  @override void invalidate() => _cache.invalidate();
  @override void dispose() => _cache.dispose();
}
```

**已有 mixin 和工具**：

| 工具 | 导入 | 用途 |
|------|------|------|
| `ShaderCacheMixin` | `../shared/brush_layer_mixin.dart` | lazy `brushShader` getter |
| `hashMyBrushMarks()` | `../shared/brush_hashes.dart` | 在此文件添加 hash 函数 |
| `createEmptyMask()` | `../shared/brush_warmup_utils.dart` | 预热用空 mask |
| `rasterizeBrushMask()` | `brush_rasterizer.dart` | marks → mask 纹理（原型 B） |
| `runSingleShaderPass()` | `shader_pass_util.dart` | 通用 GPU shader 调度 |
| `IncrementalRenderCache<T>` | `incremental_render_cache.dart` | 两级缓存（L1 hash + L2 增量） |

**参考**：`spot_heal_layer.dart`（mask 渲染，~160 行）、`clone_stamp_layer.dart`（batch 渲染，~195 行）

---

### Step 6：UI 面板（`my_brush_section.dart`）

```dart
class MyBrushSection extends ConsumerWidget {
  final AdjustmentParams params;
  final ValueChanged<AdjustmentParams> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myBrushStateProvider);
    final notifier = ref.read(myBrushStateProvider.notifier);
    return Column(children: [
      SectionLabel(title: tr('myBrushTitle')),
      PillChip(
        icon: Icons.brush,
        label: tr('myBrushTitle'),
        isActive: state.mode == MyBrushMode.active,
        onTap: () => notifier.setMode(
          state.mode == MyBrushMode.active
              ? MyBrushMode.inactive
              : MyBrushMode.active,
        ),
      ),
      if (state.mode == MyBrushMode.active) ...[
        const SizedBox(height: 8),
        DevelopSliderTile(
          label: tr('myBrushRadius'),
          value: state.brushRadius,
          min: 1, max: 100, fractionDigits: 0, suffix: 'px',
          onChanged: (v) => notifier.setBrushRadius(v),
        ),
        // ... 更多滑块 ...
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(tr('ClearAll')),
            onPressed: () => notifier.clearAll(),
          ),
        ),
      ],
    ]);
  }
}
```

**公共组件**（从 `widgets/develop/sections/shared.dart` 导入）：
- `SectionLabel(title:)` — 分区标题
- `PillChip(icon:, label:, isActive:, onTap:)` — 开关按钮
- `DevelopSliderTile(label:, value:, min:, max:, onChanged:)` — 滑块

---

## 3. 注册（4 处）

### 3.1 `lib/brushes/shared/brush_hashes.dart`（1 行）

添加 hash 函数：

```dart
int hashMyBrushMarks(List<MyBrushMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
```

### 3.2 `lib/core/models/adjustment_params.dart`（9 处）

| 位置 | 代码 |
|------|------|
| import | `import '../../brushes/my_brush/my_brush_model.dart';` |
| field | `final List<MyBrushMark> myBrushMarks;` |
| constructor default | `this.myBrushMarks = const [],` |
| copyWith param | `List<MyBrushMark>? myBrushMarks,` |
| copyWith body | `myBrushMarks: myBrushMarks ?? this.myBrushMarks,` |
| == operator | `listEquals(myBrushMarks, other.myBrushMarks) &&` |
| hashCode | `Object.hash(..., myBrushMarks, ...)` |
| toJson | `'myBrushMarks': myBrushMarks.map((e) => e.toJson()).toList(),` |
| fromJson | `myBrushMarks: (json['myBrushMarks'] as List<dynamic>?)?.map((e) => MyBrushMark.fromJson(e as Map<String, dynamic>)).toList() ?? const [],` |

### 3.3 `lib/brushes/brush_manifest.dart`（~8 行）

在 `brushManifests` 列表末尾添加：

```dart
BrushManifest(
  id: 'my_brush',
  titleKey: 'myBrushTitle',
  icon: Icons.brush,
  shaderAsset: 'assets/shaders/brushes/my_brush.frag',
  hasMarks: _hasMyBrushMarks,
  layerFactory: _makeMyBrushLayer,
  hashMarks: _hashMyBrushMarks,
  tool: DevelopTool.myBrush,
),
```

并在文件底部添加对应的 3 个 private helper：

```dart
bool _hasMyBrushMarks(AdjustmentParams p) => p.myBrushMarks.isNotEmpty;
int _hashMyBrushMarks(AdjustmentParams p) => hashMyBrushMarks(p.myBrushMarks);
BrushLayerProvider _makeMyBrushLayer(ui.FragmentProgram p) =>
    MyBrushLayerProvider(program: p);
```

### 3.4 `lib/state/tools/develop_tool_state.dart`（1 行）

在 `DevelopTool` enum 中添加（注意位置——影响 vertical panel tab 顺序）：

```dart
enum DevelopTool {
  // ... existing ...
  dodgeBurn,
  myBrush,    // ← 新增
  watermark,
  // ...
}
```

---

## 4. 界面集成（自动，无需手动注册）

以下集成点**已通过 BrushManifest 自动处理**，新增画笔无需修改：

| 集成点 | 文件 | 机制 |
|--------|------|------|
| Pass 判断 | `pass_config.dart` | `brushManifests.any((m) => m.hasMarks(p))` |
| Shader 加载 | `render_state.dart` | `brushShaderProgramsProvider` 动态加载 |
| Compose 图层 | `multi_pass_preview.dart` | `brushManifests` 循环创建 layer |
| 导出 | `export_queue_state.dart` | `brushManifests` 循环创建 registry |
| GPU 预热 | `gpu_warmup.dart` | `brushManifests` 循环创建 warmup 任务 |
| Overlay Stack | `preview_area.dart` | `_buildOverlayIfActive` + manifest 循环 |
| 横向面板 rail | `horizontal_adjustment_panel.dart` | `brushManifests` 循环生成 |
| 纵向面板 tabs | `vertical_adjustment_panel.dart` | `brushManifests` 循环生成 |
| Exit listener | 两个面板文件 | `deactivateBrush(m.id, ref)` 统一退出 |
| State 导出 | `providers.dart` | 你的 `my_brush_state.dart` 中的 provider 在此添加 export |
| Section 导出 | `develop_sections.dart` | 你的 section 类在此添加 export |

---

## 5. 翻译

在 `assets/translations/en-US.json` 和 `zh-CN.json` 中添加：

```json
"myBrushTitle": "My Brush",
"myBrushRadius": "Radius",
"myBrushHardness": "Hardness",
// ... 其他 UI 文本 ...
```

清除按钮复用已有的 `"ClearAll"` key，无需新建。

---

## 6. 验证清单

- [ ] `flutter analyze` 零错误零警告
- [ ] 激活画笔后 overlay 显示，停用后隐藏
- [ ] 笔画渲染正确（预览 + 管线产出一致）
- [ ] 切换工具时画笔自动退出
- [ ] Compose 叠加顺序正确（最后注册 = 最上层）
- [ ] Shader 预热无报错（首笔不卡顿）
- [ ] 导出含画笔标记的图像
- [ ] 移动端纵向面板 tab 正常
- [ ] 桌面端横向面板 rail 正常
- [ ] 翻译文本正确显示（中/英）
- [ ] 更新 `NEXT_SESSION_PROMPT.md` 中的关键数字速查表

---

## 7. 注册点总览

| # | 文件 | 行数 | 性质 |
|---|------|------|------|
| 1 | `brush_hashes.dart` | 3 | 添加 hash 函数 |
| 2 | `adjustment_params.dart` | ~9 | 类型安全的 marks list 声明 |
| 3 | `brush_manifest.dart` | ~11 | 元数据注册 + 3 个 helper |
| 4 | `develop_tool_state.dart` | 1 | Dart enum |
| 5 | `providers.dart` | 1 | export state provider |
| 6 | `develop_sections.dart` | 1 | export section |
| 7 | `en-US.json` + `zh-CN.json` | ~10 | 翻译文本 |

**6 个自包含文件 + 7 处胶水代码**。其中 4/7 处只有 1 行。

---

## 8. 参考文件速查

| 想看什么 | 去哪个文件 |
|----------|-----------|
| **最简模板**（原型 B） | `lib/brushes/spot_heal/` 全部 6 文件 |
| **B 类 overlay 基类** | `lib/brushes/shared/effect/base_effect_overlay.dart` |
| **B 类 painter 基类** | `lib/brushes/shared/effect/base_effect_painter.dart` |
| **B 类 gesture handler** | `lib/brushes/shared/effect/effect_gesture_handler.dart` |
| **A 类 overlay 基类** | `lib/brushes/shared/stamp/base_stamp_overlay.dart` |
| **A 类 painter 基类** | `lib/brushes/shared/stamp/base_stamp_painter.dart` |
| **A 类 gesture handler** | `lib/brushes/shared/stamp/stamp_gesture_handler.dart` |
| **A 类 compositor** | `lib/brushes/shared/stamp/stamp_compositor.dart` |
| **复杂模板**（原型 B + per-mark 参数） | `lib/brushes/dodge_burn/` |
| **完整 committed preview**（原型 A） | `lib/brushes/clone_stamp/` |
| BrushLayerProvider 接口 | `lib/render/brush_layer_provider.dart` |
| IncrementalRenderCache | `lib/render/incremental_render_cache.dart` |
| 坐标变换 API | `lib/utils/brush_coord_utils.dart` |
| OOB 预览 API | `lib/utils/brush_preview_utils.dart` |
| 路径采样 API | `lib/utils/path_brush_tracker.dart` |
| 纹理生命周期 API | `lib/state/utils/texture_notifier.dart` |
| Shader 编译流程 | `docs/rendering/RENDERING_RULES.md` |
| 项目整体架构 | `NEXT_SESSION_PROMPT.md` |
