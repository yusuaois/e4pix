# GPU 着色器预热

## 问题

spot_remove / healing shader 首次 `picture.toImage()` 曾耗时 8-27s（JIT 编译），因 387 个 float uniform 超过 GPU push constant 限制。

## 解决方案

**纹理传参 + for 循环**——2026-07-06 实施：

| 着色器 | Float Uniform | Sampler |
|--------|---------------|---------|
| spot_remove | 3 (uSize + uSpotCount) | 2 (uImage + uSpotData) |
| healing | 3 (uSize + uMarkCount) | 2 (uImage + uMarkData) |
| spot_heal | 3 | 2 |
| compose | 11 | 9 |

- **纹理编码**：`encodeMarksToTexture()`（`lib/brushes/shared/spot_data_texture.dart`）将 mark 数据编码为 192×1 RGBA8 纹理，16-bit 双通道精度
- **Shader 解码**：`unpack16()` + `readSpot()` / `readMark()` + `for` 循环替代 unrolled 展开
- **编译产物**：spot_remove 622KB→16KB，healing 1237KB→28KB

## 预热架构

```
CPU 加载（启动时）
  shaderWarmupProvider → FragmentProgram.fromAsset() × 10
  仅 CPU 侧初始化，不触发 GPU 工作
        │
        ▼
GPU 预热（首帧渲染后，addPostFrameCallback 链）
  runWarmupChain() → 逐帧执行 warmup 任务
    帧 0: spot_removal.warmup()
    帧 1: healing.warmup()
    帧 2: spot_heal.warmup()
    帧 3: dodge_burn.warmup()
    帧 4: compose.warmup()
  每帧之间 UI 渲染优先，不竞争 raster thread
```

## Session 级守卫

`_warmupDone` / `_warmupRunning` 静态标志（`lib/render/gpu_warmup.dart`），确保整个 app 生命周期内预热只执行一次，防止 `MultiPassPreview` 被反复重建时重复触发。

## 关键文件

| 文件 | 作用 |
|------|------|
| `lib/render/gpu_warmup.dart` | `buildWarmupTasks()` + `runWarmupChain()` |
| `lib/brushes/shared/spot_data_texture.dart` | `encodeMarksToTexture()` 纹理编码 |
| `lib/brushes/clone_stamp/clone_stamp_layer.dart` | `_runSpotRemovePass()` + `warmup()` |
| `lib/brushes/healing/healing_layer.dart` | `_runHealingPass()` + `warmup()` |
| `lib/widgets/preview/multi_pass_preview.dart` | `_runProviderWarmup()` 触发点 |
| `lib/state/render/render_state.dart` | `shaderWarmupProvider` CPU 加载 |

## 开发注意

- `encodeMarksToTexture()` 创建的纹理必须在 pass 完成后 dispose（`try/finally`）
- 启动时不碰 GPU——推迟到首帧渲染后通过 addPostFrameCallback 执行
- FragmentShader 对象跨帧复用，不要每帧 `fragmentShader()`
- 修改 `.frag` 后在 `e4pix_shader/` 中 `flutter build bundle`，复制到 `assets/shaders/` 重命名为 `.shader`
