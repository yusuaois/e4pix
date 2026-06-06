## 🚀 新功能 (New Features)
* **通知**：新增导出与监听通知
* **LUT预览**：新增LUT预览功能

## 🐛 问题修复 (Bug Fixes)
* 修复安卓长按导出与AI无法调出的问题

## 🛠️ 底层改进 (Under the Hood)
* **性能优化**：FullPipelineRenderer 缓存命中时使用 `clone()` 替代全图 GPU 拷贝
* **性能优化**：直方图渲染分辨率减半 + DevelopPassCache 复用，减少直方图更新频率
* **性能优化**：ShotsNotifier 参数更新改用 List.of + 索引定位，避免 list comprehension 的闭包分配；更新前检查索引不存在则跳过
* **性能优化**：TetherStatusBar 改为 ConsumerWidget 内部 watch ticker，避免父级 develop_screen 每秒全局重建

---

> 📦 **下载提示**：手机架构分包。多数安卓手机选 **arm64-v8a**；不确定就下 **universal**（通用包，体积大但全设备可用）。
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__