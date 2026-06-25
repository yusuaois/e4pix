## 🚀 新功能 (New Features)
* **HDR 曝光融合**：支持多选 2+ 张不同曝光图片进行 Mertens 曝光融合，带三阶段进度条（解码→融合→保存），自动检测无损/有损源格式输出 PNG 或 JPEG

## ⚡ 性能优化 (Performance)

## 🐛 问题修复 (Bug Fixes)
* **TopBar 溢出修复**：多选模式下的 HDR、同步调整按钮纳入自适应溢出系统，空间不足时自动收进「⋯」菜单；退出多选按钮常驻显示；已选N张标签与全选按钮移入自适应区内，不再与溢出菜单挤占空间
* **按钮颜色统一**：多选退出、HDR、同步调整、AI 调色建议按钮移除特殊高亮色，与其他工具栏按钮一致
* **退出手势**：修复全屏预览时退出手势导致应用直接退出的问题
* **画笔主体**：修复画笔主体不可用的问题
* **画笔错位**：修复画笔在裁切旋转时错位的问题

## 🛠️ 底层改进 (Under the Hood)
* **HDR 保存逻辑统一**：新增 `RawFormats.isLossless()` 方法，RAW/PNG/TIFF/BMP 统一输出 PNG，JPEG/WebP 输出 JPEG，移除冗余的 RAW 专用保存路径
* **SR Provider 优化**：超分辨率服务改用 `appendDefaultProviders()` 自动选择最佳硬件加速（Android: NNAPI，Windows: DirectML，macOS: CoreML）
* **SR 风险提示**：超分辨率实验性提示增加手机端可能闪退的警告
* **退出确认**：Android 返回手势/按键现在弹出与桌面端相同的退出确认对话框，复用 `AppExitGuard.showExitConfirmDialog()` 逻辑
* **日志持久化**：Debug 日志改为同步写入磁盘（`debug_log.txt`），崩溃后不丢失；启动时自动加载历史日志
* **诊断日志补全**：在 20 个关键模块中补充 40+ 处 debugPrint（FFI 解码、网络请求、联机会话、LUT/水印/预设、GPU 计算等），覆盖所有静默 catch 块和关键状态变更
* **降级Onnxruntime V2库**：将库降级至1.23.0，解决Android部分库冲突问题

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__