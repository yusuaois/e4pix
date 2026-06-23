## ✨ 新改变  (New Changes)
* **UI调整**：调整部分UI
* **触摸区域优化**：预设栏、裁剪面板、局部调整面板的按钮触摸区域增大
* **镜头自动检测加载态**：点击「Auto」按钮时显示旋转加载图标，完成后恢复
* **输入框键盘优化**：AI 设置和预设重命名对话框的输入框支持 Tab 跳转和 Enter 确认
* **并发导出**：支持 1-4 张图片并发导出，可在设置中配置
* **LUT 多选导入**：导入 LUT 时支持多选文件批量导入

## 🚀 新功能 (New Features)
* **键盘切换图片**：按 ↓ 切换下一张图，按 ↑ 切换上一张图（可在快捷键设置中自定义）
* **超分辨率 Section**：新增超分辨率功能，支持 2x Real-ESRGAN，局部预览 + 全图导出，后台 Isolate 执行

## 🐛 问题修复 (Bug Fixes)
* **图片切换崩溃**：修复快速切换图片时 `Image has been disposed` 和 `ref used after unmount` 两个未处理异常
* **导出队列按钮**：修复导出队列过长时底部按钮被推出屏幕
* **国际化补全**：修复镜头错误提示、HD 加载标签、预设加载失败提示、水印 EXIF 字段标签等硬编码英文

## ⚡ 性能优化 (Performance)
* **参数监听**：优化参数监听逻辑
* **预览隔离**：拖动分割线时不再触发密集的预览重绘
* **遮罩光标**：将局部调整的光标从 MaskPainter 拆分为独立的 MaskCursorPainter + RepaintBoundary，鼠标移动不再触发遮罩全量重绘
* **EXIF 解析 Isolate 迁移**：将 JPEG 的 EXIF 解析（含完整解码）移至 Isolate.run() 与图片解码并行执行，避免主线程阻塞
* **SR 预览裁切优化**：用 GPU 侧裁切替代全图像素读取（96MB → 64KB）
* **TopBar 监听优化**：canUndo/canRedo 使用 `.select()` 独立监听
* **PulsingDot 隔离**：联机拍摄脉冲动画添加 RepaintBoundary，不再带动状态栏重绘
* **列表滚动**：Tether 缩略图列表添加 itemExtent 优化滚动性能

## 🛠️ 底层改进 (Under the Hood)
* **异步安全**：为 develop_screen.dart 中 3 处 await 后缺失的 `mounted` 检查添加防护，消除页面切换时的潜在崩溃
* **LensSection 重构**：从 ConsumerWidget 重构为 ConsumerStatefulWidget，支持加载状态管理
* **MaskPainter 拆分**：将光标渲染逻辑拆分为独立的 MaskCursorPainter 类，职责分离
* **SAM 迁移**：EdgeSAM 分割服务迁移至 onnxruntime_v2，统一 ONNX 运行时
* **错误日志**：为导出队列、镜头数据库、图片状态等静默 catch 块添加 debugPrint 日志
* **日志格式统一**：所有 debugPrint 统一为 `[TagName] message` 格式
* **流订阅管理**：gPhoto2 控制器的 stdout/stderr 订阅正确存储并在停止时取消
* **防重复操作**：XMP 导出添加防重复点击
* **并发安全**：导出队列使用 `_claimNext` 防止并发 worker 抢占同一任务

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__