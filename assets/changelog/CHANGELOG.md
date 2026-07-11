## 🚀 新功能 (New Features)
* **加深减淡 (Dodge & Burn)**：新增加深减淡画笔——Screen/Multiply 混合 + 三色调范围遮罩（Shadows/Midtones/Highlights），per-mark 参数冻结，支持混用不同模式/范围的笔画
* **污点修复 (Spot Heal)**：新增污点修复画笔
* **Compose 图层化架构**：所有像素画笔接入 Compose 图层系统，新画笔只需注册 BrushLayerProvider 即可自动覆盖预览/导出/水印/分割对比全通路
* **修复画笔 (Healing Brush)**：新增修复画笔工具，使用边界匹配修复算法——沿笔刷边界采样干净背景色，对克隆像素做全局光照补偿，可消除小面积缺陷
* **海绵工具 (Sponge)**：新增海绵工具画笔——使用 HSL 色彩空间调整饱和度，支持饱和/去饱和模式切换、流量控制、羽化遮罩；按 (mode, flow) 分组 GPU 渲染，per-mark 参数冻结
* **历史记录画笔 (History Brush)**：从 History 面板选中的冻结快照恢复像素、3-sampler GPU 着色器（当前画面+历史快照+mark 纹理）、无取样模式始终处于绘画状态。
* **历史记录面板 (History Panel)**：参数调整和笔画结束自动捕获条目、120×80 缩略图事件驱动惰性生成、点击回退完整编辑状态、长按设为 History Brush 取样源、Bottom Sheet UI 集成到横/竖屏按钮


## ⚡ 性能优化 (Performance)
* **GPU 着色器预热自动触发**：图片加载后自动预编译所有 brush shader 的 GPU Pipeline State Object，消除首次笔画 7-30s 的 JIT 编译卡顿。预热通过 `addPostFrameCallback` 链逐帧执行，与 UI 光栅化错开
* **Compose pass 替代内联渲染**：所有画笔通过单一 Compose pass 混合
* **FragmentShader 跨帧复用**：三个 brush layer 的 `_shader` getter 通过 `_cachedShader` 复用 FragmentShader 对象，避免重复创建

## 🛠️ 底层改进 (Under the Hood)
* **插槽化提取**：新增 `BrushManifest` 单点注册机制 + `lib/brushes/shared/` 共享基础设施（`ShaderCacheMixin`、`brush_hashes`、`createEmptyMask`、`deactivateBrush`）。新增画笔从 14 个集成点 ~131 行胶水代码缩减至 4 个集成点 ~38 行。所有集成点（shader 加载、pass 判断、layer 创建、预热、面板 tabs/rail、exit listener、overlay stacking）改为 manifest 循环驱动，消除 per-brush 复制粘贴。详见 `docs/brushes/ADDING_A_BRUSH.md`
* **画笔文件重组**：三个像素画笔从散落目录迁至 `lib/brushes/clone_stamp/`、`healing/`、`spot_heal/`，每个画笔 6 文件自包含
* **整体管线简化**：移除所有逐画笔参数传递链（spotRemoveProgram/healingProgram），改为 Compose registry 统一管理
* **提取 GPU 预热工具**：新增 `lib/render/gpu_warmup.dart`，`buildWarmupTasks()` / `runWarmupChain()` 为 `MultiPassPreview` 和 `PreviewArea` 共用
* **`_PreviewContent` 迁移**：从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`，以支持 `initState` 预热触发

## 🐛 问题修复 (Bug Fixes)
* **MultiPassPreview ref-after-unmount 崩溃**：`_captureComposeGuide` 以 fire-and-forget 调用，内部 `await picture.toImage()` 后未检查 `mounted` 即调用 `ref.read()`，widget unmount 时抛出 "Using ref when widget has been unmounted" 异常。同步路径和异步路径各加 `if (!mounted) return;` 守卫
* **原型 B 画笔实时预览不刷新**：修复 sponge/dodge_burn/spot_heal 三个 overlay 的 `shouldRepaint` 使用引用相等比较 `List<Offset>` 的 bug——笔画预览因 `_strokePoints` 原地 mutate 而永不刷新。改为 `listEquals` 值比较 + 传递时 `List.from` 拷贝

## 🛠️ 底层改进 (Under the Hood)
* **共享基础设施扩展**：新增 `StampMark` 接口（`lib/brushes/shared/stamp_mark.dart`）、`stamp_painter_utils.dart`（4 个光标绘制函数 + `kHardEdgeThreshold` 常量）、`base_stamp_painter.dart`（泛型 CustomPainter 基类）、`base_stamp_overlay.dart`（泛型 ConsumerState 基类，封装合成预览、手势、生命周期）
* **注释风格统一清理**：移除全部 `// ──` 和 `// ═══` 装饰性注释，统一为中文、无句号、精炼简洁风格；删除 `SpotMark.copyWith`（无调用方）、`listenParamsClear`（死代码）
* **P1 修复顺带完成**：`_compositedPreview != widget.sourceImage` 死代码（→ `_disposeComposited()` 方法）、`hasContent` mutable flag（→ 直接条件）、`kHardEdgeThreshold` 命名常量、`compositedCount` 在 `listenRenderedHashes` 中重置

## 🐛 问题修复 (Bug Fixes)
* **已有画笔选区修复**：修复在已有画笔时使用智能选区只能选中底图的问题
* **裁剪逆旋转数学修正**：`CropParams.inverseMap` 和 `outputToSourceNorm` 中逆旋转迭代次数 `(4-o)%4` 在 o=1 时产生正向旋转而非逆向，导致 screen↔source 来回变换不闭合。修正为 `o%4` 次迭代
* **裁剪下屏幕半径计算修正**：`sourceRadiusToScreen` 丢弃 `forwardToOutputNorm` 的 y 分量，orientation=1/3 时 ox 不依赖于 sx 导致屏幕半径恒为 0。改用双分量欧几里得距离
* **画笔点击误退出**：`_finishBrush()` 在 tap（未拖动）时错误清除选区退出画笔模式。修复：统一调用 `_commitBrushStroke()` 提交单点笔画
* **画笔栏无法取消选中**：`_MaskListItem.onTap` 始终设为 `local.id`，点击已激活项无反应。修复：`isSelected` 时设为 `null` 实现 toggle 取消
* **Committed preview 持久化**：切换工具时未渲染完的 committed preview 通过静态字段持久化，避免闪回旧画面后跳变

## 🛠️ 底层改进 (Under the Hood)
* **画笔图层顺序可配置**：Compose 图层叠加顺序从固定的 manifest 注册顺序改为用户可拖拽配置。在纵向面板 TabBar 右侧、横向面板 _ToolRail 中新增 `Icons.layers` 按钮 → 弹出 `showModalBottomSheet` 内含 `ReorderableListView` 拖拽排序。顺序持久化到 SharedPreferences。Compose shader 无需改动——仅调整 `BrushLayerRegistry` 中 provider 顺序即可控制 last-write-wins 叠加
* **裁剪预览隐藏局部调整紫色遮罩**：裁剪模式下不再渲染 `LocalMaskOverlay`

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__