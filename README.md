<div align="center">

<img src="docs/logo_horizontal.svg" alt="e4pix Logo" width="350"/>

# e4pix

<img src="docs/screenshot_android_horizontal.png" alt="e4pix Screenshot"/>

一个能与相机联机拍摄的调色修图工具

[简体中文](#简体中文) | [English](#english)

</div>

---

## 简体中文

一个跨平台的修图工具。最初是为联机拍摄做的——相机拍一张，设备上立刻能调。后来把常见图片格式也加了进来，所以现在 RAW、JPEG、PNG 都能改。

### 功能

调色这块是核心：曝光、对比度、高光阴影、白平衡、HSL、RGB 曲线，外加 LUT（`.cube` / `.vlt`，支持 A、B 双槽串联，每张图各自记忆）。降噪分明度和颜色两路，导出时可选 CPU 并行或 GPU。还有锐化和胶片颗粒。

局部调整支持线性和径向渐变，以及画笔（流量、硬度、加擦、自动蒙版）。选区有两种：智能区域按相近色扩选，主体分割能自动抠出主体、再用正负点细化。

裁剪、旋转、翻转、拉直都有。取色器可以读任意像素的 RGB 和 HEX。

联机方面，USB 直连或监控文件夹都行；RAW+JPEG 同时传时，可以只保留 RAW。多张图能批量同步参数，调好的参数随图持久化（`.e4pix.json` 边车文件），换台机器也带得走。

导出走后台队列，排着慢慢跑，不挡着你继续修别的；支持批量、文件名模板、随时取消。

其余：预设、撤销重做、星标旗标筛选、直方图、前后对比、解码缓存（切回看过的图秒开）、AI 调色建议（Claude / GPT / DeepSeek）、Material You 主题（跟随壁纸或自选种子色）、应用内更新、自定义键位。

### 平台

Windows、Android 已测。macOS / Linux / iOS 还没适配。

### 编译

LibRaw 是 submodule，clone 时带上 `--recursive`：

```bash
git clone --recursive https://github.com/yusuaois/e4pix.git
cd e4pix
```

已经 clone 过的：

```bash
git submodule update --init --recursive
```

需要：

- Flutter SDK
- Windows：Visual Studio 2022 + “使用 C++ 的桌面开发”
- Android：Android Studio + NDK

LibRaw 会在 `flutter run` 时自动编译。EdgeSAM 模型已经打包在 `assets/models/`。

```bash
flutter pub get
flutter run -d windows   # 或 -d android
```

AI 功能在「设置 → AI 配置」里填 Key，只存在本地。

### 许可证

[GPL v3](LICENSE)

---

## English

A cross-platform photo editor. It started out for tethered shooting—shoot on the camera, edit on the computer right away. Common image formats came later, so these days it handles RAW, JPEG, and PNG alike.

### Features

Color grading is the heart of it: exposure, contrast, highlights/shadows, white balance, HSL, RGB curves, plus LUTs (`.cube` / `.vlt`, with A and B slots that chain together, remembered per image). Denoise splits into luma and color, with a choice of CPU (parallel) or GPU at export. There's sharpening and film grain too.

Local adjustments cover linear and radial gradients, plus a brush (flow, hardness, add/erase, auto-mask). Two ways to make selections: Smart Region grows by color similarity, and Subject Segmentation pulls out the subject automatically, then lets you refine with positive/negative points.

Crop, rotate, flip, straighten—all there. The color picker reads RGB and HEX off any pixel.

For tethering, USB or folder watching both work; when RAW+JPEG come in together, you can keep just the RAW. Edits sync across multiple shots and persist with each image (`.e4pix.json` sidecar files), so they travel with you to another machine.

Export runs through a background queue—it chugs along without blocking the rest of your work; batch, filename templates, cancel anytime.

The rest: presets, undo/redo, star/flag filtering, histogram, before/after compare, a decode cache (revisited images open instantly), AI grading suggestions (Claude / GPT / DeepSeek), Material You theming (follows wallpaper or pick your own seed color), in-app updates, custom keybindings.

### Platforms

Tested on Windows and Android. macOS / Linux / iOS aren't supported yet.

### Build

LibRaw is a submodule—clone with `--recursive`:

```bash
git clone --recursive https://github.com/yusuaois/e4pix.git
cd e4pix
```

If you've already cloned:

```bash
git submodule update --init --recursive
```

Requirements:

- Flutter SDK
- Windows: Visual Studio 2022 + Desktop development with C++
- Android: Android Studio + NDK

LibRaw builds automatically during `flutter run`. EdgeSAM models are bundled in `assets/models/`.

```bash
flutter pub get
flutter run -d windows   # or -d android
```

For AI features, add your API key under **Settings → AI Configuration**. It's stored locally only.

### License

[GPL v3](LICENSE)
