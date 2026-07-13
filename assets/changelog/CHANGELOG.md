## ✈️ 新变化 (New Changes)
* **UI精简**：删除侧边栏中的crop入口

## 🚀 新功能 (New Features)

## ⚡ 性能优化 (Performance)

## 🛠️ 底层改进 (Under the Hood)
* **插槽化提取**：新增 `BrushManifest` 单点注册机制 + `lib/brushes/shared/` 共享基础设施（`ShaderCacheMixin`、`brush_hashes`、`createEmptyMask`、`deactivateBrush`）。新增画笔从 14 个集成点 ~131 行胶水代码缩减至 4 个集成点 ~38 行。所有集成点（shader 加载、pass 判断、layer 创建、预热、面板 tabs/rail、exit listener、overlay stacking）改为 manifest 循环驱动，消除 per-brush 复制粘贴。详见 `docs/brushes/ADDING_A_BRUSH.md`
* **画笔文件重组**：三个像素画笔从散落目录迁至 `lib/brushes/clone_stamp/`、`healing/`、`spot_heal/`，每个画笔 6 文件自包含
* **整体管线简化**：移除所有逐画笔参数传递链（spotRemoveProgram/healingProgram），改为 Compose registry 统一管理
* **提取 GPU 预热工具**：新增 `lib/render/gpu_warmup.dart`，`buildWarmupTasks()` / `runWarmupChain()` 为 `MultiPassPreview` 和 `PreviewArea` 共用
* **`_PreviewContent` 迁移**：从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`，以支持 `initState` 预热触发

## 🐛 问题修复 (Bug Fixes)
* **MultiPassPreview ref-after-unmount 崩溃**：`_captureComposeGuide` 以 fire-and-forget 调用，内部 `await picture.toImage()` 后未检查 `mounted` 即调用 `ref.read()`，widget unmount 时抛出 "Using ref when widget has been unmounted" 异常。同步路径和异步路径各加 `if (!mounted) return;` 守卫
* **原型 B 画笔实时预览不刷新**：修复 sponge/dodge_burn/spot_heal 三个 overlay 的 `shouldRepaint` 使用引用相等比较 `List<Offset>` 的 bug——笔画预览因 `_strokePoints` 原地 mutate 而永不刷新。改为 `listEquals` 值比较 + 传递时 `List.from` 拷贝

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__