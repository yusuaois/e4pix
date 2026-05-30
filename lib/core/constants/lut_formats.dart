/// LUT 文件格式
class LutFormats {
  LutFormats._();

  /// 支持的 LUT 扩展名（小写，含点）
  static const Set<String> extensions = {'.cube', '.vlt'};

  /// 路径是否为支持的 LUT（大小写不敏感）
  static bool isLut(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return extensions.contains(path.substring(dot).toLowerCase());
  }

  /// 是否为松下 .vlt
  static bool isVlt(String path) => path.toLowerCase().endsWith('.vlt');
}