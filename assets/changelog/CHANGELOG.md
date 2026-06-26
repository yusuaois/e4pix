## 🚀 新功能 (New Features)
* **Top Bar 多选模式过渡动画**：进入/退出多选模式时左侧区 220ms cross-fade 过渡（`AnimatedSwitcher`），符合项目统一动画规范
* **Debug Log 分组折叠**：按 Tag 分组显示日志，每组可折叠/展开，支持一键 Expand All / Collapse All
* **Debug Log 时间范围筛选**：新增 1m / 5m / All 时间范围过滤，快速定位近期日志
* **Debug Log JSON 导出**：导出菜单支持 Text 和 JSON 两种格式，JSON 包含结构化字段（time/tag/message/level）
* **Debug Log 搜索增强**：搜索现在同时匹配消息文本和 Tag 名称
* **HDR 图像对齐**：手持 HDR 拍摄时自动校正相机抖动，融合前执行 Harris 角点检测 + NCC 块匹配 + RANSAC 仿射估计，消除重影
* **Settings 页面 UI 改版**：所有设置区块包裹 floating card（`panelBg` + 圆角 10），与 Develop Screen 风格统一
* **版本号点击查看更新日志**：点击 About 区块的版本号弹出 `ChangelogDialog`，从打包的 `assets/changelog/CHANGELOG.md` 读取并渲染 Markdown
* **Top Bar 多选模式布局优化**：进入多选后左侧区替换为 [✕] + "N selected" + 全选按钮，右侧保留 HDR/同步/导出等操作

## ⚡ 性能优化 (Performance)

## 🐛 问题修复 (Bug Fixes)
* **日志跨天日期错误**：日志格式升级为 `[YYYY-MM-DD HH:MM:SS]`，重启后旧格式条目自动兼容回退
* **日志同步 UTF-8 编码错误**：修复 `syncNewEntriesFromDisk` 中 `String.fromCharCodes` 导致中文等多字节字符损坏的问题，改用 `utf8.decode`
* **HDR 连续调用崩溃**：修复首次 HDR 完成后再次调用报 `setState() called after dispose()` 的问题，改为 `await showDialog` + microtask 模式
* **HDR Isolate 资源泄漏**：修复 `Isolate.spawn` 失败时 `ReceivePort` 未关闭导致后续调用卡死的问题，增加 spawn 错误捕获 + 10 分钟超时保护
* **子 Isolate 日志不进 Debug Log Manager**：修复 Dart Isolate 不共享静态变量导致 `setupIsolateLogging()` 空操作的根本问题，改为显式传递 `logFilePath`；新增 `syncNewEntriesFromDisk()` 使 UI 实时同步子 Isolate 日志
* **Markdown 行内代码无背景**：`UpdateDialog` 和 `ChangelogDialog` 的 `MarkdownStyleSheet` 缺少 `code:` 样式，`` `backtick` `` 文本现在有 `subtleBorder` 背景

## 🛠️ 底层改进 (Under the Hood)
* **HDR 对齐代码审查修复**：RANSAC 坐标系统一（降采样空间运行 + 仅放大平移）、Homography 改为 8×8 稳定求解、金字塔尺寸链与 `_downsample` 一致、降采样抗锯齿（scale > 2 时 3×3 box blur）
* **HDR 代码质量**：提取共享亮度系数/进度常量到 `hdr_constants.dart`、命名化所有魔法数字、修复 `w`/`h` 可空类型、消除双重 snackbar 错误处理
* **Debug Log UI 优化**：新增文本搜索、Filter chip 计数、展开追踪 O(n)→O(1)、3 秒轮询磁盘同步
* **Debug 模式开关持久化**：开关状态通过 `SharedPreferences` 保存，应用重启后自动恢复
* **Debug Log 代码审查修复**：`_GroupItem` 重构为 sealed class 消除 force-unwrap；提取 `_buildChipBase` / `_buildEntryRow` 消除重复代码；Filter 计数尊重时间范围筛选；JSON 导出补全日期字段
* **CI workflow 更新**：`build_release.yml` 改为从 `assets/changelog/CHANGELOG.md` 读取 changelog
---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__