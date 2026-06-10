import '../../state/providers.dart';

/// 图片格式定义（RAW + 标准图片）
class RawFormats {
  RawFormats._();

  /// 支持的 RAW 扩展名（小写，含点）
  static const Set<String> extensions = {
    '.arw',
    '.cr2',
    '.cr3',
    '.nef',
    '.nrw',
    '.raf',
    '.dng',
    '.orf',
    '.rw2',
    '.pef',
    '.srw',
    '.rwl',
  };

  /// 标准图片扩展名
  static const Set<String> standardExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  };

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  /// 是否为支持的 RAW
  static bool isRaw(String path) => extensions.contains(_ext(path));

  /// 是否为标准图片（JPG/PNG…）
  static bool isStandard(String path) =>
      standardExtensions.contains(_ext(path));

  /// 是否为任何受支持的图片（RAW 或标准）
  static bool isSupported(String path) => isRaw(path) || isStandard(path);

  /// 去扩展名的基名（用于 RAW+JPG 同名去重）
  static String baseKey(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = slash < 0 ? path : path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    return (dot < 0 ? name : name.substring(0, dot)).toLowerCase();
  }

  static String get displayList =>
      extensions.map((e) => e.substring(1).toUpperCase()).join(' · ');

  /// 含标准格式的展示列表
  static String get displayListAll => [
    ...extensions,
    ...standardExtensions,
  ].map((e) => e.substring(1).toUpperCase()).join(' · ');

  /// 按导入模式过滤文件列表
  /// rawPriority: 同名 RAW+标准 → 只留 RAW；无同名 RAW 的标准图保留
  /// rawOnly: 只留 RAW
  /// all: RAW + 标准 都保留
  List<String> filterByImportMode(List<String> paths, ImportMode mode) {
    switch (mode) {
      case ImportMode.rawOnly:
        return paths.where(RawFormats.isRaw).toList();
      case ImportMode.all:
        return paths.where(RawFormats.isSupported).toList();
      case ImportMode.rawPriority:
        final supported = paths.where(RawFormats.isSupported).toList();
        // 有 RAW 的基名集合
        final rawBases = <String>{};
        for (final p in supported) {
          if (RawFormats.isRaw(p)) rawBases.add(RawFormats.baseKey(p));
        }
        // 标准图片若与某 RAW 同名 → 丢弃
        return supported.where((p) {
          if (RawFormats.isRaw(p)) return true;
          return !rawBases.contains(RawFormats.baseKey(p));
        }).toList();
    }
  }
}
