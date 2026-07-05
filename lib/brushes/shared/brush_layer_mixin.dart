import 'dart:ui' as ui;

/// Mixin providing lazy [ui.FragmentProgram] -> [ui.FragmentShader] caching.
///
/// All four brush layer providers share this identical pattern. Subclasses
/// must provide [brushProgram] (the compiled [ui.FragmentProgram]), and the
/// mixin exposes [brushShader] — a lazily-created, cached [ui.FragmentShader].
///
/// Usage (inside a class that also implements [BrushLayerProvider]):
/// ```dart
/// class MyLayerProvider with ShaderCacheMixin implements BrushLayerProvider {
///   @override
///   final ui.FragmentProgram brushProgram;
///   MyLayerProvider({required ui.FragmentProgram program}) : brushProgram = program;
///   // ... use brushShader instead of _shader
/// }
/// ```
mixin ShaderCacheMixin {
  /// The compiled fragment program. Concrete class must provide this.
  ui.FragmentProgram get brushProgram;

  ui.FragmentShader? _cachedShader;

  /// Lazily-created fragment shader, cached after first access.
  ui.FragmentShader get brushShader =>
      _cachedShader ??= brushProgram.fragmentShader();
}
