## ✨ 新改变  (New Changes)
* **UI调整**：调整部分UI
* **触摸区域优化**：预设栏、裁剪面板、局部调整面板的按钮触摸区域增大
* **镜头自动检测加载态**：点击「Auto」按钮时显示旋转加载图标，完成后恢复
* **输入框键盘优化**：AI 设置和预设重命名对话框的输入框支持 Tab 跳转和 Enter 确认
* **并发导出**：支持一次性导出至多4张图片

## 🚀 新功能 (New Features)
* **键盘切换图片**：按 ↓ 切换下一张图，按 ↑ 切换上一张图（可在快捷键设置中自定义）
* **超分辨率 Section**：新增超分辨率功能，支持2x，目前仅cpu

## 🐛 问题修复 (Bug Fixes)
* **图片切换崩溃**：修复快速切换图片时 `Image has been disposed` 和 `ref used after unmount` 两个未处理异常
* **国际化补全**：修复镜头错误提示、HD 加载标签、预设加载失败提示、水印 EXIF 字段标签等硬编码英文
* **导出队列**：修复导出队列UI问题

## ⚡ 性能优化 (Performance)
* **参数监听**：优化参数监听逻辑
* **预览隔离**：拖动分割线时不再触发密集的预览重绘
* **遮罩光标**：将局部调整的光标从 MaskPainter 拆分为独立的 MaskCursorPainter + RepaintBoundary，鼠标移动不再触发遮罩全量重绘
* **EXIF 解析 Isolate 迁移**：将 JPEG 的 EXIF 解析（含完整解码）移至 Isolate.run() 与图片解码并行执行，避免主线程阻塞
* **列表滚动**：Tether 缩略图列表添加 itemExtent 优化滚动性能

## 🛠️ 底层改进 (Under the Hood)
* **异步安全**：为 develop_screen.dart 中 3 处 await 后缺失的 `mounted` 检查添加防护，消除页面切换时的潜在崩溃
* **LensSection 重构**：从 ConsumerWidget 重构为 ConsumerStatefulWidget，支持加载状态管理
* **MaskPainter 拆分**：将光标渲染逻辑拆分为独立的 MaskCursorPainter 类，职责分离
* **SAM 迁移**：EdgeSAM 分割服务迁移至 onnxruntime_v2，统一 ONNX 运行时
* **错误日志**：为导出队列、镜头数据库、图片状态等静默 catch 块添加 debugPrint 日志
* **流订阅管理**：gPhoto2 控制器的 stdout/stderr 订阅正确存储并在停止时取消
* **防重复操作**：XMP 导出添加防重复点击

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__