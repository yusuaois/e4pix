/// RAW 文件格式
class RawFormats {
  RawFormats._();

  /// 支持的 RAW 扩展名（小写，含点）
  static const Set<String> extensions = {
    '.arw', '.cr2', '.cr3', '.nef', '.nrw', '.raf',
    '.dng', '.orf', '.rw2', '.pef', '.srw', '.rwl',
  };

  /// 路径是否为支持的 RAW（大小写不敏感）
  static bool isRaw(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return extensions.contains(path.substring(dot).toLowerCase());
  }

  /// 大写、无点、· 分隔
  static String get displayList =>
      extensions.map((e) => e.substring(1).toUpperCase()).join(' · ');
}