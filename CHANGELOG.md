## 🚀 新功能 (New Features)
* **HDR 曝光融合**：支持多选 2+ 张不同曝光图片进行 Mertens 曝光融合，自动检测无损/有损源格式输出 PNG 或 JPEG

## ⚡ 性能优化 (Performance)

## 🛠️ 底层改进 (Under the Hood)
* **HDR 保存逻辑统一**：新增 `RawFormats.isLossless()` 方法，RAW/PNG/TIFF/BMP 统一输出 PNG，JPEG/WebP 输出 JPEG，移除冗余的 RAW 专用保存路径
* **SR Provider 优化**：超分辨率服务改用 `appendDefaultProviders()` 自动选择最佳硬件加速（Android: NNAPI，Windows: DirectML，macOS: CoreML）

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__