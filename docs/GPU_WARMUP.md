# GPU 着色器预热技术文档

## 1. 问题概述

e4pix 的三个像素画笔（图章、修复画笔、污点修复）在**首次使用时**，`picture.toImage()` 耗时极长（7-30 秒），导致 UI 卡顿。后续使用正常（12-60ms）。

### 受影响的着色器

| 着色器 | Float Uniform | Sampler | 首次 `toImage()` 耗时 |
|--------|---------------|---------|----------------------|
| spot_remove (图章) | 387 (2+1+64×6) | 1 | ~8s |
| healing (修复画笔) | 387 (2+1+64×6) | 1 | ~27s |
| spot_heal (污点修复) | 3 | 2 | ~90ms（从不卡） |
| compose | 11 (2+1+8) | 9 | ~15ms |

**关键发现**：uniform 数量与首次耗时强相关。spot_heal 只有 3 个 float → 从不卡。`_kMaxSpots=32`（195 float）时不卡 → 改成 `_kMaxSpots=64`（387 float）后开始卡。

### 根因

GPU 驱动程序对着色器做 JIT（Just-In-Time）编译。387 个 float uniform（1548 字节）超过了 GPU push constant 的典型限制（128-256 字节），触发驱动使用 uniform buffer 路径。首次执行时驱动需要：
1. 编译 SPIR-V → 平台着色器语言（MSL/GLSL/SPIR-V）
2. 创建 Pipeline State Object (PSO)
3. 分配和绑定 uniform buffer / descriptor sets
4. 基于运行时行为生成优化变体（循环次数等）

## 2. 预热架构

### 两层预热策略

```
┌─ 第一层：CPU 加载（app 启动时，~150ms）────────────────┐
│ shaderWarmupProvider                                     │
│   └── FragmentProgram.fromAsset() × 10                  │
│         └── fragmentShader() × 10 (CPU 侧初始化)         │
│   不执行任何 GPU 工作！                                   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─ 第二层：GPU 预热（首帧渲染后，addPostFrameCallback 链）─┐
│ MultiPassPreview._runProviderWarmup()                    │
│   ├── devClone = finalImage.clone()                      │
│   ├── 重新读取 shader provider（防 FutureProvider 时序） │
│   ├── 按需创建 brush layer provider                      │
│   └── _runWarmupChain():                                 │
│       帧 0: spot_removal.warmup(64 marks, 2400×1600)     │
│       帧 1: healing.warmup(64 marks, 2400×1600)          │
│       帧 2: spot_heal.warmup(2400×1600)                  │
│       帧 3: compose.warmup(2400×1600)                    │
│       每帧之间：UI 渲染优先，warmup 不竞争 raster thread  │
└─────────────────────────────────────────────────────────┘
```

### 设计原则

1. **启动时不碰 GPU**：`shaderWarmupProvider` 仅做 CPU 加载，`picture.toImage()` 提交 GPU 工作到 raster thread，会与 UI 帧光栅化竞争 → 启动时丢帧。

2. **首次渲染后预热**：有真实 `developOutput`（真实图片尺寸和像素格式），PSO key 与实际使用完全匹配。

3. **addPostFrameCallback 链**：每个 warmup 任务在上一帧光栅化完成后才启动，确保 UI 帧始终优先。

4. **64 个 mark 满载预热**：GPU 驱动对不同循环次数生成不同 JIT 变体。1 个 mark 预热不能加速 64 个 mark 的实际使用。

## 3. 关键代码路径

### 3.1 CPU 加载（`lib/state/render/render_state.dart`）

```dart
final shaderWarmupProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    ref.watch(_allShadersProvider.future),     // 9 个主 shader
    ref.watch(healingShaderProgramProvider.future), // healing（独立加载）
  ]);
  // CPU 侧完成，GPU PSO 由 MultiPassPreview 按帧触发
});
```

### 3.2 GPU 预热链触发（`lib/widgets/preview/multi_pass_preview.dart`）

```dart
// _runRender() 成功后：
final warmupImage = result.developOutput ?? result.finalImage;
if (!_hasWarmedUpProviders && !_warmupRunning) {
  _hasWarmedUpProviders = true;
  _warmupRunning = true;
  _runProviderWarmup(warmupImage, tw, th);
}
```

### 3.3 Provider 创建与预热任务构建

```dart
void _runProviderWarmup(ui.Image? developOutput, int tw, int th) {
  // 1. 克隆图像（独立生命周期）
  final devClone = developOutput.clone();

  // 2. 重新读取 shader provider（首帧 _runRender 调用 ref.read 时
  //    FutureProvider 可能尚未 resolved，.value 为 null）
  final spotProg = ref.read(spotRemoveShaderProgramProvider).value;
  final healProg = ref.read(healingShaderProgramProvider).value;
  final spotHealProg = ref.read(spotHealShaderProgramProvider).value;
  final composeProg = ref.read(composeShaderProgramProvider).value;

  // 3. 按需创建 layer（如果 _runRender 中未创建）
  if (spotProg != null) _spotLayer ??= SpotRemovalLayerProvider(program: spotProg);
  if (healProg != null) _healLayer ??= HealingLayerProvider(program: healProg);
  if (spotHealProg != null) _spotHealLayer ??= SpotHealLayerProvider(program: spotHealProg);

  // 4. 构建任务列表
  final tasks = [
    if (_spotLayer != null) ('spot_removal', () => _spotLayer!.warmup(devClone, tw, th)),
    if (_healLayer != null) ('healing',      () => _healLayer!.warmup(devClone, tw, th)),
    if (_spotHealLayer != null) ('spot_heal', () => _spotHealLayer!.warmup(devClone, tw, th)),
    if (composeProg != null)  ('compose',     () => _warmupComposeShader(composeProg, devClone, tw, th)),
  ];

  // 5. 启动递归 addPostFrameCallback 链
  _runWarmupChain(tasks, 0, devClone);
}
```

### 3.4 addPostFrameCallback 递归链

```dart
void _runWarmupChain(tasks, index, devClone) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!mounted || index >= tasks.length) {
      devClone.dispose();
      _warmupRunning = false;
      return;
    }
    final (name, task) = tasks[index];
    await task();  // 执行一个 warmup 任务（可能耗时 7-30s）
    _runWarmupChain(tasks, index + 1, devClone);  // 下一帧执行下一个
  });
}
```

### 3.5 各 Provider 的 warmup() 实现

**图章** (`clone_stamp_layer.dart`)：
```dart
Future<void> warmup(developOutput, tw, th) async {
  final dummies = List.generate(_kMaxSpots, (i) => SpotMark(
    source: Offset(0, 0), target: Offset(i * 0.0001, i * 0.0001),
    radius: 0.0001, hardness: 1.0,
  ));
  final result = await _runSpotRemovePass(input: developOutput, spots: dummies);
  result.dispose();
}
// 使用 _cachedShader（FragmentShader 复用，Flutter 官方推荐）
```

**修复画笔** (`healing_layer.dart`)：同样结构，使用 `_kMaxMarks` 个 dummy mark。

**污点修复** (`spot_heal_layer.dart`)：创建空 mask 纹理 → `runSingleShaderPass`，2 sampler（base + emptyMask），3 float uniforms。

### 3.6 FragmentShader 复用（三个 Provider 均实现）

```dart
ui.FragmentShader? _cachedShader;
ui.FragmentShader get _shader => _cachedShader ??= _program.fragmentShader();
```

Flutter 官方文档推荐："你可以跨帧复用 FragmentShader 对象；这比每帧创建新的 FragmentShader 更高效。"

## 4. 已发现并修复的 Bug

### Bug #1：`setFloat` 越界导致预热完全失效

**现象**：预热从第一天起就从未成功执行任何 draw call。

**代码**：
```dart
for (int i = 0; i < 512; i++) {
  shader.setFloat(i, 0.0);  // spot_remove 只有 387 float → i=387 抛 IndexError
}
// ← drawRect 从未执行，PSO 从未创建
```

**原因**：Flutter 的 `FragmentShader.setFloat()` 在 debug 和 release 模式都有越界检查，`index >= _floatCount` 时抛 `IndexError`。

**修复**：改为精确传递每个 shader 的 floatCount（spot_remove=387, healing=387, spot_heal=3, compose=11）。

**修复状态**：✅ 已修复（代码已改，未提交）

### Bug #2：预热用 1 个 mark，实际用 N 个 mark——GPU JIT 变体不匹配

**现象**：预热 clone_stamp 的 `toImage()` 只需 12ms，但用户第一笔仍需 8s。

**原因**：GPU 驱动对不同循环次数（count=1 vs count=N）生成不同 JIT 优化变体。预热 1 个 mark → 驱动编译了"单迭代"变体 → 用户多笔时驱动首次编译"多迭代"变体 → 卡顿。

**修复**：预热传满 `_kMaxSpots=64` 个 mark。

**修复状态**：✅ 已修复（代码已改，未提交）

### Bug #3：spot_heal 缺 sampler 1（base + mask = 2 samplers）

**原因**：`_gpuWarmupOneShader` 只绑定 `sampler 0`，spot_heal 实际需要 `sampler 0 + sampler 1`。

**修复状态**：✅ 已修复（provider.warmup() 正确使用 2 个 sampler）

### Bug #4：compose shader 完全不在预热列表

**原因**：compose shader（9 sampler, 11 float）从未被预热。首次 compose pass 在用户操作关键路径上创建 PSO。

**修复状态**：✅ 已修复（`_warmupComposeShader` 加入预热链）

### Bug #5：FutureProvider 时序——首帧 `ref.read().value` 返回 null

**现象**：首帧后 warmup 只有 compose 一个任务，brush provider 缺失。

**原因**：`_runRender()` 中 `ref.read(spotRemoveShaderProgramProvider).value` 在首帧时返回 null（FutureProvider 尚未 resolved）。`_spotLayer ??= ...` 未执行。

**修复**：`_runProviderWarmup()` 中重新 `ref.read()` 并 `??=` 创建 layer（此时 provider 已 resolved）。

**修复状态**：✅ 已修复（代码已改，未提交）

### Bug #6：首帧 `developOutput` 为 null

**现象**：预热被跳过（条件检查 `developOutput != null`）。

**原因**：首帧没有 mask 也没有 compose marks → `result.developOutput` 为 null。

**修复**：用 `result.finalImage` 作为 fallback。

**修复状态**：✅ 代码已改，但预热仍不自动触发，见 Bug #7

### Bug #7（未修复）：图片加载后 `_runRender()` 似乎不被调用

**现象**：用户加载图片、等待 5 分钟，没有任何 `[Timer] _runRender` 日志，也没有 `[Warmup]` 日志。

**修复方向**：
- 在 `initState()` 和 `didUpdateWidget()` 中添加 debugPrint 确认 `_runRender()` 是否被调用
- 检查 `_isRendering` 是否被并发渲染占用
- 检查 `gen != _generation` 是否导致提前 return
- 确认 `MultiPassPreview` 在图片加载时是否已挂载

## 5. 性能计时系统

`[Timer]` 日志覆盖全管线：

| 日志 | 来源 | 含义 |
|------|------|------|
| `[Timer] _runRender: Xms` | `multi_pass_preview.dart` | 一次渲染总耗时 |
| `[Timer] pipeline total: Xms` | `full_pipeline_renderer.dart` | 全管线渲染耗时 |
| `[Timer] layer <id> render: Xms` | `full_pipeline_renderer.dart` | 单个 brush layer 渲染 |
| `[Timer] GPU toImage(WxH): Xms` | `shader_pass_util.dart` | 单次 `picture.toImage()` |
| `[Timer] compose total (N layers): Xms` | `full_pipeline_renderer.dart` | compose pass 总耗时 |

## 6. 开发注意

- **`FragmentShader.setFloat(i, v)` 在 `i >= floatCount` 时抛 `IndexError`**，必须传精确数量
- **GPU 驱动对不同循环次数生成不同 JIT 变体**，预热必须传满 batch 大小
- **`picture.toImage()` 提交 GPU 工作到 raster thread**，与 UI 帧光栅化共享线程
- **启动时不要做 GPU 工作**，推迟到首帧渲染后通过 addPostFrameCallback 执行
- **FragmentShader 对象跨帧复用**（官方推荐），不要每帧 `fragmentShader()`
