## 🚀 新功能 (New Features)
* **镜头矫正**：手动或自动进行镜头矫正（lensfun）
* **透视矫正**：手动透视矫正

## 🐛 问题修复 (Bug Fixes)
* 联机拍摄或文件夹监听结束后不清除照片

## ⚡ 性能优化 (Performance)
* 解码预览缓存按系统内存自适应（3→2~12）
* 预览区消除快速预览闪烁
* ShotsNotifier 增加路径缓存
* Shader 并行加载
* 缓存容量设置改为 0-20 滑块，取消固定选项

## 🛠️ 底层改进 (Under the Hood)
* 合并笔刷 StateProvider
* 提取共享防抖/节流工具类


---

> 📦 **下载提示**：手机架构分包。多数安卓手机选 **arm64-v8a**；不确定就下 **universal**（通用包，体积大但全设备可用）。
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__