# 如何新增画笔 — 开发者指南

> 当前已提取公共工具层（坐标变换、路径采样、纹理生命周期）、A/B 两类 Overlay 基类委托模式、BrushManifest 单点注册机制、和跨画笔时间排序渲染。
> 新增画笔只需创建 **6 个自包含文件** + 在 **3 个代码注册点**（+ 翻译）添加少量胶水代码。
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
| 是否需要 Alt+取样 | 是（历史画笔除外） | **否** |
| 是否有 clone source | 是（历史画笔除外） | **否** |
| committed preview 生命周期 | 有（hash 匹配） | **无** |
| 渲染方式 | 逐 mark shader pass | mask 光栅化 + 单 pass |
| Overlay 基类 | **`BaseStampOverlayState`** | **`BaseEffectOverlayState`** |
| Gesture Handler | **`StampGestureHandler`** | **`EffectGestureHandler`** |
| Painter 基类 | **`BaseStampPainter`** | **`BaseEffectPainter`** |
| Mark 接口 | `implements StampMark` | `implements StampMark` |
| createdAt 来源 | `_strokeTimestamp` 共享 | `DateTime.now()` per stroke |
| 参考模板 | `clone_stamp/`、`healing/` | **`spot_heal/`（最简）** |

**建议**：如果是原地修改型（涂抹即生效），选择原型 B，从 `spot_heal/` 复制起步，overlay 只需 ~40 行（继承 `BaseEffectOverlayState`）。

---

## 2. Step-by-Step

### Step 1：数据模型（`my_brush_model.dart`）

创建 `@immutable` mark 类，**必须实现 `StampMark` 接口**，至少包含：

```dart
import '../shared/stamp/stamp_mark.dart';

@immutable
class MyBrushMark implements StampMark {
  @override final Offset target;    // 归一化源图坐标 [0..1]
  @override final double radius;    // 归一化半径
  @override final double hardness;  // 0..1，1=硬边
  @override final DateTime createdAt; // 创建时间戳，用于跨画笔时间排序
  // 按需添加画笔特有参数（如 mode、opacity、flow）

  const MyBrushMark({
    required this.target,
    required this.createdAt,
    this.radius = 0.02,
    this.hardness = 1.0,
  });

  // 必须实现：==、hashCode、toJson、fromJson
  // fromJson 中解析 createdAt 用 StampMark.parseCreatedAt(json)
}
```

**关键规则**：

- **`createdAt` 为 required**（未发版，无需向后兼容）
- **构造器为 `const`**（纯数据对象）
- **`fromJson` 解析用 `StampMark.parseCreatedAt(json)`**：已提取为 static helper
- **`source` getter**：A 类需存储并返回 source 坐标；B 类返回 `target` 即可（`Offset get source => target`）
- **`toJson` 序列化**：`createdAt.toUtc().toIso8601String()` 统一格式

需要的枚举也在此定义。

**参考**：`spot_heal_model.dart`（最简，3 字段 + createdAt）、`dodge_burn_model.dart`（复杂，6 字段 + 2 枚举 + createdAt）


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

  // 读取 marks——通过 params.brushMasks['my_brush'] 泛型 map
  List<T> _marks<T extends StampMark>() =>
      ref.read(currentParamsNotifierProvider).brushMarks['my_brush']?.cast<T>() ??
      const [];

  void _setMarks(List<StampMark> marks) {
    final params = ref.read(currentParamsNotifierProvider);
    ref.read(currentParamsNotifierProvider.notifier)
        .update(params.copyWith(brushMarks: {...params.brushMarks, 'my_brush': marks}));
  }

  // 必须实现：addMarkAt / addStrokesBatch（含 createdAt）
  void addMarkAt(Offset target, double radiusNorm, double hardness) {
    final mark = MyBrushMark(
      target: target, radius: radiusNorm, hardness: hardness,
      createdAt: DateTime.now(),  // ← 单点标记独立时间戳
    );
    _addMarkRaw(mark);
  }

  void addStrokesBatch(List<Offset> targets, double radiusNorm, double hardness) {
    if (targets.isEmpty) return;
    final ts = DateTime.now();  // ← 笔画内共享时间戳
    final updated = <StampMark>[..._marks<MyBrushMark>()];
    for (final t in targets) {
      updated.add(MyBrushMark(
        target: t, radius: radiusNorm, hardness: hardness, createdAt: ts,
      ));
    }
    _setMarks(updated);
  }

  void removeMark(int index) { ... }
  void clearAll() { ... }
}

final myBrushStateProvider =
    NotifierProvider<MyBrushNotifier, MyBrushState>(MyBrushNotifier.new);
```

**关键规则**：

- **`addMarkAt` → `DateTime.now()`**：单点标记各自取当前时间
- **`addStrokesBatch` → `final ts = DateTime.now()`**：笔画内所有 marks 共享同一时间戳，时间排序按笔画粒度
- **marks 存储在 `params.brushMarks['my_brush']`**：泛型 Map 统一管理，无需在 `adjustment_params.dart` 添加 per-brush 字段
- **读 marks 用 `?.cast<T>()`** 而非 `as List<T>?`

**参考**：`spot_heal_state.dart`（~120 行，最简 B 类模板）、`healing_state.dart`（A 类模板）


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

## 3. 注册（3 处代码 + 1 处翻译）

### 3.1 `lib/brushes/shared/brush_hashes.dart`（3 行）

添加 hash 函数（用于 `IncrementalRenderCache` 缓存键和 committed-preview 匹配）：

```dart
int hashMyBrushMarks(List<StampMark> marks) =>
    Object.hashAll(marks.map((m) => m.hashCode));
```

> **注意**：如果 marks 的渲染输出与 `createdAt` 无关（缓存可跨时间排序复用），可排除 `createdAt` 手动构造 hash，如 `hashSpotHealMarks`。

### 3.2 `lib/brushes/brush_manifest.dart`（~25 行）

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
  overlayFactory: _makeMyBrushOverlay,
  marksFromJson: (list) => list.map((j) => MyBrushMark.fromJson(j)).toList(),
  deactivate: (ref) => ref.read(myBrushStateProvider.notifier).setMode(MyBrushMode.inactive),
  sectionFactory: (p, oc) => MyBrushSection(params: p, onChanged: oc),
),
```

并在文件底部添加对应的 5 个 private helper：

```dart
// hasMarks / hashMarks
bool _hasMyBrushMarks(AdjustmentParams p) =>
    (p.brushMarks['my_brush'] ?? const []).isNotEmpty;
int _hashMyBrushMarks(AdjustmentParams p) =>
    Object.hashAll((p.brushMarks['my_brush'] ?? const []).map((m) => m.hashCode));

// layerFactory
BrushLayerProvider _makeMyBrushLayer(ui.FragmentProgram p) =>
    MyBrushLayerProvider(program: p);

// overlayFactory
Widget? _makeMyBrushOverlay(OverlayFactoryParams p) {
  final st = p.ref.watch(myBrushStateProvider);
  if (st.mode != MyBrushMode.active) return null;
  return MyBrushOverlay(
    imageDisplaySize: p.imageDisplaySize,
    crop: p.crop,
    sourceWidth: p.sourceWidth,
    sourceHeight: p.sourceHeight,
    sourceImage: p.sourceImage,
  );
}
```

> **重要**：不再需要在 `adjustment_params.dart` 中添加 per-brush 字段。marks 统一存储在 `Map<String, List<StampMark>> brushMarks` 中，以 brush ID 为 key。`marksFromJson` 回调负责从 JSON 反序列化为具体类型。

### 3.3 `lib/state/tools/develop_tool_state.dart`（1 行）

在 `DevelopTool` enum 中添加（注意位置——影响 vertical panel tab 顺序）：

```dart
enum DevelopTool {
  // ... existing ...
  dodgeBurn,
  sponge,
  myBrush,    // ← 新增
  historyBrush,
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
| 时间排序渲染 | `full_pipeline_renderer.dart` | `_renderTimeOrderedStamps()` 泛型排序+合并 |
| 导出 | `export_queue_state.dart` | `brushManifests` 循环创建 registry |
| GPU 预热 | `gpu_warmup.dart` | `brushManifests` 循环创建 warmup 任务 |
| Overlay Stack | `preview_area.dart` | `_buildOverlayIfActive` + manifest 循环 |
| 横向面板 rail | `horizontal_adjustment_panel.dart` | `brushManifests` 循环生成 |
| 纵向面板 tabs | `vertical_adjustment_panel.dart` | `brushManifests` 循环生成 |
| 纵向面板 section | `vertical_adjustment_panel.dart` | `manifest.sectionFactory` 泛型生成 |
| 横向面板 section | `horizontal_adjustment_panel.dart` | `manifest.sectionFactory` 泛型生成 |
| Exit listener | 两个面板文件 | `manifest.deactivate` 泛型退出 |
| Sidecar 反序列化 | `sidecar_service.dart` | `manifest.marksFromJson` 统一入口 |

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
- [ ] 跨画笔时间排序正常（多画笔交替绘制时按实际顺序叠加）
- [ ] 切换工具时画笔自动退出
- [ ] Compose 叠加顺序正确（最后注册 = 最上层，由时间排序统一管理）
- [ ] Shader 预热无报错（首笔不卡顿）
- [ ] 导出含画笔标记的图像
- [ ] 移动端纵向面板 tab 正常（自动从 manifest 生成）
- [ ] 桌面端横向面板 rail 正常（自动从 manifest 生成）
- [ ] 翻译文本正确显示（中/英）
- [ ] Sidecar 文件序列化/反序列化正确（含 `createdAt`）
- [ ] 更新 `NEXT_SESSION_PROMPT.md` 中的关键数字速查表

---

## 7. 注册点总览

| # | 文件 | 行数 | 性质 |
|---|------|------|------|
| 1 | `brush_hashes.dart` | 3 | 添加 hash 函数 |
| 2 | `brush_manifest.dart` | ~25 | manifest 条目 + helpers（含 marksFromJson、deactivate、sectionFactory） |
| 3 | `develop_tool_state.dart` | 1 | Dart enum 值 |
| 4 | `en-US.json` + `zh-CN.json` | ~10 | 翻译文本 |

**6 个自包含文件 + 3 处代码胶水 + 1 处翻译**。其中 2/3 代码处只有 1~3 行。

> **不再需要改 `adjustment_params.dart`**：marks 统一存储在 `Map<String, List<StampMark>> brushMarks` 中。
> **不再需要改 `providers.dart`**：overlay + section 直接 import state 文件，无需 barrel export。
> **不再需要改 `develop_sections.dart`**：`manifest.sectionFactory` 泛型生成面板。
> **不再需要改 `brush_deactivate.dart`**：`manifest.deactivate` 泛型退出。
> **不再需要改 `full_pipeline_renderer.dart`**：`_renderTimeOrderedStamps()` 完全泛型。
> **不再需要改两个面板文件**：section + deactivate 通过 manifest 回调泛型分发。

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
| **StampMark 接口 + parseCreatedAt** | `lib/brushes/shared/stamp/stamp_mark.dart` |
| **复杂模板**（原型 B + per-mark 参数） | `lib/brushes/dodge_burn/`、`lib/brushes/sponge/` |
| **完整 committed preview**（原型 A） | `lib/brushes/clone_stamp/`、`lib/brushes/healing/` |
| **A 类特殊：快照源** | `lib/brushes/history_brush/` |
| BrushLayerProvider 接口 | `lib/render/brush_layer_provider.dart` |
| IncrementalRenderCache | `lib/render/incremental_render_cache.dart` |
| 坐标变换 API | `lib/utils/brush_coord_utils.dart` |
| OOB 预览 API | `lib/utils/brush_preview_utils.dart` |
| 路径采样 API | `lib/utils/path_brush_tracker.dart` |
| 纹理生命周期 API | `lib/state/utils/texture_notifier.dart` |
| **技术文档** | |
| 图章 (Clone Stamp) | `docs/brushes/SPOT_REMOVAL.md` |
| 修复画笔 (Healing) | `docs/brushes/HEALING_BRUSH.md` |
| 污点修复 (Spot Heal) | `docs/brushes/SPOT_HEAL.md` |
| 加深减淡 (Dodge & Burn) | `docs/brushes/DODGE_BURN.md` |
| 海绵工具 (Sponge) | `docs/brushes/SPONGE.md` |
| 历史画笔 (History Brush) | `docs/brushes/HISTORY_BRUSH.md` |
| Shader 编译流程 | `docs/rendering/RENDERING_RULES.md` |
| 项目整体架构 | `NEXT_SESSION_PROMPT.md` |
