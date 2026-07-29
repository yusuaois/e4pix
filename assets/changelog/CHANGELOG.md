## ✈️ 新变化 (New Changes)
> **代码质量**：20 个文件的 build() 超标方法重构为私有辅助 Widget 方法
> **历史系统架构重构**：拆分为 HistoryNotifier（undo/redo/条目/防抖/跨图隔离）+ HistoryPanelNotifier（面板同步/revert/brushSource），按图片独立保存/恢复编辑历史，新增"保留编辑历史"设置开关  
> **画笔清除修复**：修复 A 类画笔清除后旧笔触残留的 Bug，修复多画笔切换时其它画笔旧痕迹不刷新的旧 Bug

## 🚀 新功能 (New Features)

## ⚡ 性能优化 (Performance)

## 🛠️ 底层改进 (Under the Hood)
* build() 超标方法重构，主 build() 缩减
* watermark_section 内部 widget 类（_DropdownTile/_ColorTile/_SegmentedTile 等）拆分为更小组件
* 用 userEditVersion 区分切图与编辑，替代 `_isApplying` flag
* panelVersion 替代 committedRevision，加载时也递增
* `_prunedEntries` 追踪 undo 裁剪条目，redo 恢复，新 commit 清空
* `_runRender` 前比对 widget.params 与 provider，跳过旧帧避免缓存污染
* marks 清零时全量失效所有 layer 缓存，杜绝跨 provider L1 命中过期链式结果

## 🐛 问题修复 (Bug Fixes)
* 修复 A 类画笔清除后画新笔画时旧笔触残留（IncrementalRenderCache 未失效）
* 修复多画笔间切换后某画笔旧痕迹不清除（单 provider 路径不改缓存导致）
* 修复图片切换时画笔 overlay 可能使用上一张图的 developOutput 纹理
* 删除历史系统死代码 `resetToNeutral()`（零调用点，无运行时影响）

## ✨ 改进 (Improvements)
* 编辑设置页新增"保留编辑历史"开关，默认开启，支持 zh-CN / en-US
* 切换图片时自动退出活跃画笔，防止 overlay 引用过期图片数据

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__