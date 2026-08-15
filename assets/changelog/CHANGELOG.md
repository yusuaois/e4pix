## ✈️ 新变化 (New Changes)
> **导入权限修复**：修复手机从文件夹导入新移入 RAW 文件不显示（Android 13+ 需「所有文件访问」权限）  
> **分段渲染超清**：主预览像 PS 一样只加载一次、放大按需变清晰，100% 显示真实像素  

## 🚀 新功能 (New Features)

## ⚡ 性能优化 (Performance)
* 主预览改为单次全分辨率解码，消除二次预览跳变

## 🛠️ 底层改进 (Under the Hood)
* 新增 `StoragePermissionService` / `NotificationPermissionService` 集中权限申请
* 选图导入与 tether 监听共用「所有文件访问」权限请求

## 🐛 问题修复 (Bug Fixes)
* 修复手机从文件夹导入时新移入的 RAW 文件不显示（缺「所有文件访问」权限）

## ✨ 改进 (Improvements)
* 选图界面支持下拉刷新
* 导入 RAW 前自动引导开启「所有文件访问」权限
* 放大到 100% 显示真实像素，不再模糊

---

> 📦 **下载提示**：
> - **Windows**: Portable ZIP 免安装版
> - **macOS**: DMG 安装包（未签名，首次打开需右键 > 打开）
> - **Linux**: AppImage（推荐，多数发行版通用）或 Portable tar.gz 免安装包
> - **Android**: 多数手机选 **arm64-v8a**；不确定就下 **universal**
>
> 此版本由 GitHub Actions 自动构建生成。
> SHA: __SHA__