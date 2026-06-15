## 🚀 新功能 (New Features)
* **镜头矫正**：手动或自动进行镜头矫正（lensfun）
* **透视矫正**：手动透视矫正

## 🐛 问题修复 (Bug Fixes)
* 联机拍摄或文件夹监听结束后不清除照片
* 修复自动矫正阻塞

## ⚡ 性能优化 (Performance)
* 解码预览缓存按系统内存自适应（3→2~12）
* 预览区消除快速预览闪烁
* ShotsNotifier 增加路径缓存
* Shader 并行加载
* 缓存容量设置改为 0-20 滑块，取消固定选项

## 🛠️ 底层改进 (Under the Hood)
* 增加linux与macos构建
* 添加安卓签名
* 添加MSIX签名逻辑前置
* 合并笔刷 StateProvider
* 提取共享防抖/节流工具类
* 优化AI调色提示词
* UI节流下沉至参数节流


---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__