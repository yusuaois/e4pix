## ✈️ 新变化 (New Changes)
> **历史系统架构重构**：拆分为 HistoryNotifier（undo/redo/条目/防抖/跨图隔离）+ HistoryPanelNotifier（面板同步/revert/brushSource），按图片独立保存/恢复编辑历史，新增"保留编辑历史"设置开关

## 🚀 新功能 (New Features)

## ⚡ 性能优化 (Performance)

## 🛠️ 底层改进 (Under the Hood)
* 用 userEditVersion 区分切图与编辑，替代 `_isApplying` flag
* panelVersion 替代 committedRevision，加载时也递增
* `_prunedEntries` 追踪 undo 裁剪条目，redo 恢复，新 commit 清空

## 🐛 问题修复 (Bug Fixes)

## ✨ 改进 (Improvements)
* 编辑设置页新增"保留编辑历史"开关，默认开启，支持 zh-CN / en-US

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__