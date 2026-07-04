## 🚀 新功能 (New Features)
* **污点修复 (Spot Heal)**：新增 PS 风格污点修复画笔
* **Compose 图层化架构**：所有像素画笔接入 Compose 图层系统，新画笔只需注册 BrushLayerProvider 即可自动覆盖预览/导出/水印/分割对比全通路
* **修复画笔 (Healing Brush)**：新增 PS 风格修复画笔工具，使用边界匹配修复算法——沿笔刷边界采样干净背景色，对克隆像素做全局光照补偿，可消除小面积缺陷
* **图章改名**：UI 名称从"污点修复/Spot Removal"改为"图章/Clone Stamp"

## ⚡ 性能优化 (Performance)
* **GPU 着色器预热自动触发**：图片加载后自动预编译所有 brush shader 的 GPU Pipeline State Object，消除首次笔画 7-30s 的 JIT 编译卡顿。预热通过 `addPostFrameCallback` 链逐帧执行，与 UI 光栅化错开
* **Compose pass 替代内联渲染**：所有画笔通过单一 Compose pass 混合
* **Pass Config 集中化**：新增 `lib/render/pass_config.dart`，8 个纯函数统一判断 pass 是否激活，消除 5 个文件中的重复检查逻辑。
* **FragmentShader 跨帧复用**：三个 brush layer 的 `_shader` getter 通过 `_cachedShader` 复用 FragmentShader 对象，避免重复创建
* **数学常量提取**：新增 `lib/core/constants/math_constants.dart`，定义 `kParamEpsilon = 0.001`。

## 🛠️ 底层改进 (Under the Hood)
* **画笔文件重组**：三个像素画笔从散落目录迁至 `lib/brushes/clone_stamp/`、`healing/`、`spot_heal/`，每个画笔 6 文件自包含
* **整体管线简化**：移除所有逐画笔参数传递链（spotRemoveProgram/healingProgram），改为 Compose registry 统一管理
* **提取 GPU 预热工具**：新增 `lib/render/gpu_warmup.dart`，`buildWarmupTasks()` / `runWarmupChain()` 为 `MultiPassPreview` 和 `PreviewArea` 共用
* **`_PreviewContent` 迁移**：从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`，以支持 `initState` 预热触发
* **PillChip 提取**：三个画笔 section 中完全相同的 `_PillChip`（~55行×3）提升为公共 `PillChip` widget（`lib/widgets/develop/sections/shared.dart`）
* **IncrementalRenderCache\<T\> 泛型提取**：新增 `lib/render/incremental_render_cache.dart`——两级缓存泛型基类，三个画笔缓存缩减为顶层 hash 函数，消除 ~180 行重复缓存逻辑
* **统一画笔 hash map**：`renderedSpotsHashProvider` + `renderedHealingHashProvider` 合并为 `renderedBrushHashesProvider (Map<String, int>)`；`BrushLayerProvider` 新增 `computeMarksHash`；`multi_pass_preview` 遍历活跃 provider 自动收集 hash——新画笔无需再碰 `render_state` 或 `multi_pass_preview`
* **清理死代码**：移除 spot_heal 中无效的 `putRolling` 调用（spot_heal 不使用增量渲染）；补上 slider 拖拽结束时遗漏的 healing cache Level-1 失效

## 🐛 问题修复 (Bug Fixes)
* **修复画笔缓存陈旧**：Level 1 缓存（marks hash）加入 `developKey` 双 key 检查，修复调整曝光/曲线等参数后画面不刷新的问题
* **Committed preview 持久化**：切换工具时未渲染完的 committed preview 通过静态字段持久化，避免闪回旧画面后跳变
* **_healingCache 内存泄漏**：修复 `MultiPassPreviewState.dispose()` 中遗漏 `_healingCache.dispose()` 的问题

## 🛠️ 底层改进 (Under the Hood)

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__