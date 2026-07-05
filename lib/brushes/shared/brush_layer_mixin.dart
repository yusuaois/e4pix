import 'dart:ui' as ui;

/// 延迟创建并缓存 [ui.FragmentShader] 的 mixin
///
/// 四个画笔 layer provider 共用此模式，子类需提供 [brushProgram]
///（已编译的 [ui.FragmentProgram]），mixin 暴露 [brushShader] ——
/// 首次访问时创建，之后缓存复用
mixin ShaderCacheMixin {
  /// 已编译的 shader program，由子类提供
  ui.FragmentProgram get brushProgram;

  ui.FragmentShader? _cachedShader;

  /// 延迟创建的 fragment shader，首次访问后缓存
  ui.FragmentShader get brushShader =>
      _cachedShader ??= brushProgram.fragmentShader();
}
