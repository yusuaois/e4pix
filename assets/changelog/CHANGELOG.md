## 🚀 新功能 (New Features)
* **修复画笔 (Healing Brush)**：新增 PS 风格修复画笔工具，使用边界匹配修复算法——沿笔刷边界采样干净背景色，对克隆像素做全局光照补偿，可消除小面积缺陷
* **图章改名**：UI 名称从"污点修复/Spot Removal"改为"图章/Clone Stamp"

## ⚡ 性能优化 (Performance)
* **Pass Config 集中化**：新增 `lib/render/pass_config.dart`，8 个纯函数统一判断 pass 是否激活，消除 5 个文件中的重复检查逻辑。
* **数学常量提取**：新增 `lib/core/constants/math_constants.dart`，定义 `kParamEpsilon = 0.001`。

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