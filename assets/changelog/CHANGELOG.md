## 🚀 新功能 (New Features)
* **Settings 页面 UI 改版**：所有设置区块包裹 floating card（`panelBg` + 圆角 10），与 Develop Screen 风格统一
* **版本号点击查看更新日志**：点击 About 区块的版本号弹出 `ChangelogDialog`，从打包的 `assets/changelog/CHANGELOG.md` 读取并渲染 Markdown
* **更新日志内置为 Asset**：`CHANGELOG.md` 迁移至 `assets/changelog/`，CI 直接从此路径读取生成 GitHub Release

## ⚡ 性能优化 (Performance)

## 🐛 问题修复 (Bug Fixes)
* **子 Isolate 日志不进 Debug Log Manager**：修复 Dart Isolate 不共享静态变量导致 `setupIsolateLogging()` 空操作的根本问题，改为显式传递 `logFilePath`；新增 `syncNewEntriesFromDisk()` 使 UI 实时同步子 Isolate 日志
* **Settings tile hover 溢出圆角**：`Container` + `Clip.antiAlias` 无法裁剪 `Material` 祖先上的 ink 效果，改为 `Material` widget 作为卡片容器；各 tile 通过 `tileBorderRadius` 参数匹配底部圆角
* **Debug tile 双重圆角**：Debug 模式开启时 `SwitchListTile` 和 `ListTile` 同时应用底部圆角，改为仅最后一个 tile 应用
* **Markdown 行内代码无背景**：`UpdateDialog` 和 `ChangelogDialog` 的 `MarkdownStyleSheet` 缺少 `code:` 样式，`` `backtick` `` 文本现在有 `subtleBorder` 背景
* **缺失翻译键**：补全 `updateNoAsset`、`debugFilterAI` 等遗漏的 i18n key；移除未使用的 `versionCheck`

## 🛠️ 底层改进 (Under the Hood)
* **Debug Log UI 优化**：新增文本搜索、Filter chip 计数、展开追踪 O(n)→O(1)、3 秒轮询磁盘同步
* **Debug Log 颜色统一**：`_LogColors` / `DebugLogColors` 合并进 `AppColors`（`debugInfra` / `debugAi` / ...），`log_style.dart` + `log_entry_row.dart` 内嵌进 `debug_log_screen.dart`
* **Debug Log Screen floating card 重构**：搜索栏、过滤栏、日志列表分别包裹 floating card，12px 统一间距，过滤芯片样式对齐 PresetChip，空状态加图标，AppBar TextButton→IconButton
* **Settings tile `tileBorderRadius` 机制**：8 个 tile 文件统一新增可选参数，传递给 `ListTile.shape` / `SwitchListTile.shape` / `RadioListTile.shape`，解决 hover ink 裁剪
* **CI workflow 更新**：`build_release.yml` 改为从 `assets/changelog/CHANGELOG.md` 读取 changelog
* **Debug trailing icon 统一**：`debug_tiles.dart` 的 `Icons.chevron_right` → `Icons.arrow_forward_ios`（size 14）

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__