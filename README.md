# e4pix

跨平台 RAW 照片编辑器，专为联机拍摄和 AI 辅助调色设计。基于 Flutter + LibRaw + Fragment Shader 的实时 develop 管线。

[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-blue)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

> 此项目源于个人对 RAW 工作流的探索。目标是把"拍 → 调 → 导"的完整链路做到既快又可控，并把 AI 调色作为一个真正可用的工作环节而非噱头。

---

## 截图

> _截图待补。建议至少放两张：(1) 桌面 develop 主界面 (2) 联机模式 + AI 建议 banner_

---

## 功能

### 实时 develop 引擎

- **GPU shader 渲染**：所有调整通过单 pass fragment shader 完成，滑块拖动 60fps 响应
- **渐进式加载**：half_size + PPG 先出图（~400ms），后台升级 full_size + PPG（~3s 无感切换）
- **sRGB 色彩管理**：LibRaw 输出 16-bit linear，统一通过 sRGB LUT 转换，预览与导出视觉一致
- **AHD 导出**：导出走最高质量的 AHD demosaicing，保留 LibRaw 的全部精度

### 49 个调整参数

| 类别 | 参数数量 | 内容 |
|---|---|---|
| 基础 | 12 | 曝光、对比度、高光、阴影、白阶、黑阶、色温、色调、饱和度、自然饱和度、清晰度、纹理 |
| HSL | 24 | 8 色相区段（红/橙/黄/绿/青/蓝/紫/品）× H/S/L |
| LUT | 3 | 3D LUT 文件（.cube）、强度、当前 LUT 状态 |

### 联机拍摄（Tether）

- **相机直连**：通过 gphoto2 / libgphoto2 把相机 USB 直接接入软件，新照片自动入栏
- **文件夹监控**：监视任意目录，新文件自动加入 shot 列表
- **参数保持**：preserve 模式下新照片直接套用上一张参数，方便批量同步调色
- **多选 + 批量导出**：进度条 + 单图独立参数

### AI 辅助调色

- **多 provider**：Anthropic Claude / OpenAI GPT-4 / DeepSeek，各家 API key 独立配置
- **上下文感知**：把当前画面 + 已有的所有 49 个参数发给 AI，得到方向性建议
- **结构化输出**：返回 JSON（`reasoning` + `mood` + `adjustments` + `hsl`），可在 UI 上预览理由
- **自动建议**：联机模式下新照片到达即触发 AI 分析，结果以 banner 呈现，一键应用

### 平台支持

| 平台 | 状态 |
|---|---|
| Windows | ✓ |
| macOS | 应可工作（需自行编译 LibRaw） |
| Linux | 应可工作（需自行编译 LibRaw） |
| Android | ✓（含 libgphoto2 NDK 编译脚本） |
| iOS | 未测试 |

桌面端和手机端 UI 自适应，根据屏幕短边切换布局。中英双语界面（zh-CN / en-US）。

---

## 技术栈

- **Flutter 3.x** + Dart
- **Riverpod 2.x**：AsyncNotifier 树管理所有 mutable 状态
- **LibRaw ≥ 0.21**：RAW 解码，通过自写的 C++ FFI bridge 调用
- **Fragment Shader (GLSL)**：实时 develop 管线
- **gphoto2 / libgphoto2**：相机联机
- **Isolate**：解码、像素转换、histogram 计算全部 off-main-thread

---

## 架构

```
lib/
├── core/              # 数据模型 + 工具
│   ├── color/         #   - sRGB LUT
│   ├── lut/           #   - .cube 解析
│   └── models/        #   - AdjustmentParams / HslBands / TetheredShot
├── native/            # LibRaw FFI binding
├── render/            # 渲染管线
│   ├── raw_to_ui_image.dart    # 解码 → 下采样 → sRGB 转换
│   ├── preview_renderer.dart   # shader 主预览
│   ├── render_engine.dart      # shader 离屏渲染（histogram / AI 输入）
│   └── exporter.dart           # 全分辨率导出
├── screens/           # 顶层页面
├── services/          # 底层服务（相机、文件监控、AI 调用）
├── state/             # Riverpod notifier 树（8 个 notifier）
└── widgets/           # 复用组件
```

状态层职责清单：

| Notifier | 管理对象 |
|---|---|
| `ImageNotifier` | 当前 RAW 解码结果 + 两阶段加载 |
| `TetherSessionNotifier` | 文件夹监控会话 |
| `ShotsNotifier` | shot 列表 + 新文件入栏 |
| `CurrentParamsNotifier` | 当前画面的 49 个参数 |
| `LutNotifier` | LUT 加载状态 |
| `CameraNotifier` | 相机控制器 |
| `AIAutoNotifier` | 自动 AI 建议状态机 |
| `ExportSelectionNotifier` | 多选导出 |
| `HistoryNotifier` | 撤销 / 重做栈 |
| `PresetNotifier` | 用户预设库 |

---

## 构建

### 前置依赖

- Flutter SDK 3.x
- CMake ≥ 3.20
- LibRaw ≥ 0.21（源码或预编译二进制）
- gphoto2 二进制（如需联机功能）

### Windows

```powershell
# 1. 编译 LibRaw FFI bridge
cd native\raw_bridge
mkdir build; cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# 2. 拷贝 dll 到 Flutter runner 目录
copy build\Release\e4pix_raw.dll ..\..\..\windows\runner\Debug\

# 3. 跑应用
cd ..\..\..
flutter run -d windows
```

### Android

```bash
# 编译 libgphoto2 + LibRaw 到各 ABI
./scripts/build_android_libs.sh

# 跑应用
flutter run -d android
```

### AI 配置

应用启动后在「设置 → AI」中填入 API key。支持 provider：

- Anthropic Claude（model 默认 `claude-sonnet-4`）
- OpenAI GPT-4 / GPT-4o
- DeepSeek

API key 通过 `shared_preferences` 本地存储，不上传到任何服务器。

---

## 已知限制 / Roadmap

### 已实现
- [x] 全套基础 + HSL + LUT develop
- [x] 渐进式 RAW 加载
- [x] 联机模式（相机 + 文件夹）
- [x] AI 自动建议
- [x] 批量导出
- [x] 撤销 / 重做 + 预设系统

### 计划中
- [ ] Before / After 对比键
- [ ] 裁剪 + 拉直
- [ ] 局部调整（径向 / 渐变滤镜）
- [ ] Inpainting（Stage 6）
- [ ] iOS 适配
- [ ] DNG / TIFF 导出

---

## License

MIT