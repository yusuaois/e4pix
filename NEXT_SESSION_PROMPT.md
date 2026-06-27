# e4pix — 项目上下文 Prompt

请先阅读以下两个记忆文件了解完整项目上下文：

- `C:\Users\LHX\.claude\projects\D--Develop-Code-Projects-e4pix\memory\session-distillation.md`（项目概述 + 所有历史改动 + 已知问题）
- `C:\Users\LHX\.claude\projects\D--Develop-Code-Projects-e4pix\memory\rendering-rules.md`（渲染系统规范）

---

## 项目简介

**e4pix** 是跨平台（Windows/Linux/macOS/Android/iOS）RAW 图片调色软件。

**技术栈**：

- Flutter + Riverpod 状态管理
- FFI 调用 LibRaw（C++）解码 RAW
- GLSL Fragment Shader 渲染管线（曝光/曲线/LUT/降噪/锐化/透视/镜头校正/污点修复）
- `onnxruntime_v2` 1.23.0（锁定版本，不能用 `^1.23.0`）运行 ONNX 模型（SAM 分割 + Real-ESRGAN 超分）
- `easy_localization` 国际化（中/英），翻译文件在 `assets/translations/`

**主题**：纯中性深色主题，所有颜色定义在 `AppColors`（`lib/core/theme/app_colors.dart`），字体在 `AppTypography`（最大 16px）。

**核心渲染管线**（`FullPipelineRenderer.render()`）：

```
源图 → 降噪 → 镜头校正 → Develop(曝光/曲线/LUT/HSL/颗粒) → 污点修复 → 透视 → 裁剪 → 遮罩(局部调整) → 锐化 → 输出
```

**目录结构**：

```
lib/
├── core/           # 模型、常量、主题(app_colors/app_typography)、快捷键
├── native/         # FFI 桥接（raw_bridge.dart — LibRaw）
├── render/         # GPU 渲染管线、导出器、蒙版光栅化
├── services/       # 业务逻辑（ai/camera/export/lens/segmentation/lut/sr/hdr/debug/notifications）
├── state/          # Riverpod 状态管理（image/export/lut/params/tether/watermark/ai_auto）
├── screens/        # 页面（develop_screen / debug_log_screen / settings / keybinding）
├── widgets/        # UI 组件（develop/preview/export/settings/tether）
└── utils/          # 工具函数
```

**UI 设计模式**：

- **Floating card**：`Material(color: panelBg, shape: RoundedRectangleBorder(borderRadius: 10), clipBehavior: Clip.antiAlias)` — 必须用 `Material` 不用 `Container`，否则 ListTile ink 效果被遮挡
- **卡片间距**：`SizedBox(height: 12)`，外层 `Padding(EdgeInsets.all(12))`
- **Section label**：`AppTypography.labelSmall` + `AppColors.disabledText` + `w600` + `.toUpperCase()`，padding `fromLTRB(16, 14, 16, 6)`
- **Pill chip**：`borderRadius: 14`，选中态 `activeBg` + `lightBorder`(0.6)，未选中 `subtleBorder` + `dividerLine`(0.6)
- **Settings tile shape**：各 tile 文件暴露 `tileBorderRadius` 参数，最后一个 tile 接收底部圆角
- **动画规范**：快速动画 120ms + `Curves.easeOut`（底部面板、缩略图边框）；展开/折叠 220ms + `Curves.easeInOut`（Section、Top Bar 切换）

---

## 会话八 + 会话九的工作（污点修复 Spot Removal）

### 1. 污点修复功能全貌

新增 GPU shader 仿制图章工具。管线位置：Develop pass 之后、Perspective/Crop 之前（源图坐标空间）。

**新增文件**：
- `lib/core/models/spot_mark.dart` — 数据模型 `SpotMark(source, target, radius)`，归一化源图坐标
- `lib/state/tools/spot_remove_state.dart` — 状态管理 `SpotRemoveNotifier`，CRUD + cloneSource + samplingButtonOn
- `lib/widgets/develop/sections/spot_remove_overlay.dart` — UI 交互覆盖层（`MouseRegion` + `GestureDetector` + `CustomPaint`）
- `lib/widgets/develop/sections/spot_remove_section.dart` — 设置面板（激活/取样 pill chip、半径滑块、清除全部）
- `assets/shaders/spot_remove.shader` + `e4pix_shader/assets/shaders/spot_remove.frag` — spot 克隆 shader

### 2. 交互模型（PS 风格）

- **按住取样键**（默认 Alt，可在设置页自定义）或点击"取样"按钮 → 白色取样圈 + 十字
- **点击预览图** → 设置取样源点（绿色十字 + 圆环标记）
- **松开采样键** → 红色目标圈
- **点击/拖拽目标区域** → 从源点克隆到目标位置，shader 柔边混合
- 拖拽按间距 `radius * 1.5` 放置 spot，形成连续涂抹效果

### 3. Shader 编译流程（重要）

**编译 shader 的正确方式**（参考 CI `e4pix_shader/.github/workflows/compile_and_push.yml`）：

1. 修改 `e4pix_shader/assets/shaders/spot_remove.frag`（GLSL 源码）
2. 在 `e4pix_shader/` 目录执行 `flutter clean && flutter pub get && flutter build bundle`
3. 将 `e4pix_shader/build/flutter_assets/assets/shaders/spot_remove.frag` 复制为 `assets/shaders/spot_remove.shader`

**⚠️ 不要用 `impellerc` 直接编译**——产出格式与 Flutter 的 `FragmentProgram.fromAsset` 不兼容，会导致 shader 加载失败（`program=null`）。

### 4. 已修复的 Bug（会话八 + 会话九）

| # | Bug | 根因 | 修复 |
|---|-----|------|------|
| 1 | **Shader 从未执行** | `preview_area.dart` 的 `needFullPipeline` 条件缺少 `hasSpots`，当只有 spot removal 时走简单 `PreviewRenderer` 路径，不经过 `FullPipelineRenderer` | 加入 `params.spots.isNotEmpty` 到 `needFullPipeline` |
| 2 | **取样按钮不自动退出** | `setCloneSource` 未关闭 `samplingButtonOn`，第二次点击仍走 `setCloneSource` 而非 `addSpot` | `setCloneSource` 内置 `samplingButtonOn: false` |
| 3 | **光标消失** | Riverpod rebuild 触发假 `onExit`，清空 `_cursorPos` | `onExit` 50ms 防抖 + `_isHovering` 标志 |
| 4 | **过时快照检查** | `_onTapDown` 用上次 build 的 `state.cloneSource` 判断，可能为 null | 去掉外层 null 检查，依赖 `addSpot` 内部保护 |
| 5 | **非方形图像椭圆笔刷** | UV 空间 `distance()` 未补偿宽高比 | shader 中 `diff.x *= aspect` + `r_corrected = r * aspect` |
| 6 | **内圈硬边** | `smoothstep(r*0.6, r, d)` 中心 60% 无渐变 | 改为 `smoothstep(0.0, r_corrected, d)` |
| 7 | **isPainting 冗余重绘** | `shouldRepaint` 检查 `isPainting` 但 `paint()` 未使用 | 从 `shouldRepaint` 移除 |
| 8 | **Shader 加载失败** | 用 `impellerc` 直接编译格式不兼容 | 改用 `flutter build bundle` 编译 |

### 5. 关键设计约束

- **污点修复管线位置**：Develop 之后、Perspective/Crop 之前（源图坐标空间）
- **坐标映射**：`CropParams.outputToSourceNorm`（屏幕→源图）、`forwardToOutputNorm`（源图→屏幕）
- **Shader uniform 顺序**：`uSize(2) → uSpotCount(1) → 32×(srcX, srcY, tgtX, tgtY, radius)(160)` = 163 个 float
- **Shader 编译**：必须通过 `e4pix_shader` 项目的 `flutter build bundle` 编译，不能用 `impellerc` 直接编译

**修改文件**（会话八+九，共 20+ 文件）：
- `lib/core/models/spot_mark.dart`（新增）
- `lib/core/models/adjustment_params.dart`（+spots 字段）
- `lib/core/models/crop_params.dart`（+forwardToOutputNorm）
- `lib/core/keybindings/app_action.dart`（+samplingHold）
- `lib/core/keybindings/develop_key_handler.dart`（+samplingHold 处理）
- `lib/state/tools/spot_remove_state.dart`（新增）
- `lib/state/tools/develop_tool_state.dart`（+DevelopTool.spotRemove）
- `lib/state/params/params_state.dart`（+samplingHoldProvider）
- `lib/state/providers.dart`（+export spot_remove_state）
- `lib/state/render/render_state.dart`（+spotRemoveShaderProgramProvider）
- `lib/state/export/export_queue_state.dart`（+spotRemoveProgram 透传）
- `lib/render/full_pipeline_renderer.dart`（+spotRemoveProgram + _runSpotRemovePass）
- `lib/render/exporter.dart`（+spotRemoveProgram 透传）
- `lib/widgets/develop/develop_sections.dart`（+export spot_remove_section）
- `lib/widgets/develop/sections/spot_remove_overlay.dart`（新增）
- `lib/widgets/develop/sections/spot_remove_section.dart`（新增）
- `lib/widgets/develop/horizontal_adjustment_panel.dart`（+spotRemove section）
- `lib/widgets/preview/preview_area.dart`（+overlay + spotRemoveProgram + needFullPipeline 含 hasSpots）
- `lib/widgets/preview/multi_pass_preview.dart`（+spotRemoveProgram 参数）
- `lib/widgets/preview/split_compare_view.dart`（+spotRemoveProgram 透传）
- `lib/screens/keybinding_settings_screen.dart`（+samplingHold）
- `e4pix_shader/assets/shaders/spot_remove.frag`（新增 GLSL 源码）
- `assets/shaders/spot_remove.shader`（新增编译产物）
- `assets/translations/en-US.json` + `zh-CN.json`（+7 新 i18n keys）
- `assets/changelog/CHANGELOG.md`（+1 条目）

---

## 当前改动状态

**最新已提交 commit**：`f76e3e2 feat: Top Bar animation, Debug Log UI overhaul, debug mode persistence`（会话七）

会话八+九所有改动尚未提交（20+ 文件）。`flutter analyze` 已通过零错误零警告。

---

## 下一步工作（会话十）

### 任务 1：去除 Alt 快捷键依赖，优化移动端体验

**问题**：按 Alt 后鼠标静止不动则红圈消失（`MouseRegion` 的 `onExit` 在 rebuild 时触发）。主力客户为移动端，Alt 键无意义。

**方案**：
- 考虑移除 `samplingHoldProvider` 和 Alt hold 型 keybinding
- 取样交互统一使用"取样"按钮（toggle 模式）
- 简化 overlay 的 `isSampling` 逻辑，只依赖 `samplingButtonOn`
- 可保留 keybinding 但改为 toggle 型而非 hold 型

### 任务 2：无极画笔（连续涂抹）

**问题**：当前拖拽按 `radius * 1.5` 间距放置独立 spot，大半径时有明显间隔。Local adjustment 的 brush 是无极画笔（连续线条），体验更好。

**方案**：
- 将 `local_mask_overlay.dart` 的画笔逻辑（`BrushStroke` + 连续点插值）提取为独立的 `BrushPainter` 类
- `SpotRemoveOverlay` 复用 `BrushPainter`，拖拽时生成连续点序列
- 每个连续点作为一个独立 spot 添加（受 32 上限约束，见任务 3）
- 或改为 shader 支持连续笔画（传入点数组 + 连接线段距离判断）

**关键文件**：
- `lib/widgets/develop/sections/local/local_mask_overlay.dart` — 现有画笔逻辑
- `lib/core/models/mask_shape.dart` — `BrushStroke` 模型
- `lib/widgets/develop/sections/spot_remove_overlay.dart` — 需要改造

### 任务 3：解除 32 spot 上限

**问题**：shader 硬编码 32 个 spot × 5 uniform = 160 个 float，大范围涂抹时很快达到上限。

**方案**：
- **方案 A（多 pass）**：每 32 个 spot 一个 pass，链式调用 `_runSpotRemovePass`。简单但增加 GPU pass 数。
- **方案 B（动态 uniform）**：用 `uSpotCount` 控制实际使用数量，shader 中用循环替代展开。需验证 Flutter `FragmentShader` 是否支持动态索引。
- **方案 C（纹理传参）**：将 spot 数据编码为纹理（float texture），shader 中采样读取。无上限但实现复杂。

**推荐方案 A**：改动最小，在 `_runSpotRemovePass` 外层加循环即可。

---

## 会话七的工作（已提交为 `f76e3e2`）

Top Bar AnimatedSwitcher 动效 + Debug Log UI 全面优化（分组折叠、时间筛选、JSON 导出、Expand/Collapse All、搜索增强、Debug 模式持久化）+ 代码审查修复。详见 `session-distillation.md`。

---

## 已知问题

1. **SR Android SIGILL**：`onnxruntime_v2` 的 `libonnxruntime.so` 在部分 Android 设备上触发非法指令崩溃
2. **Sidecar 写入权限**：Android 11+ Scoped Storage 限制
3. **GPU 加速不生效**：`onnxruntime_v2` 自带 DLL 是 CPU-only 版本
4. **C++ 日志不进 DebugLogService**：`e4pix_raw.cpp` 中的 `fprintf(stderr)` 无法被 Dart 拦截
5. **pubspec.yaml msix_version 滞后**：`msix_version: 2.8.6.89` vs `version: 2.9.3+93`
6. **污点修复光标冻结**：Alt 按下/松开后 `MouseRegion.onExit` 在 rebuild 时触发（任务 1 将解决）
7. **污点修复笔刷不连续**：拖拽按 `radius * 1.5` 间距放点，有间隔（任务 2 将解决）
8. **污点修复 32 上限**：shader 硬编码 32 个 spot（任务 3 将解决）
