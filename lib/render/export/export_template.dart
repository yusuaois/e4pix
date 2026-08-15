import '../../native/raw_bridge.dart';

/// 导出文件名模板工具
///
/// 支持的占位符（大小写敏感）：
///   {name}   原文件名（不含扩展名）
///   {seq}    序号（批量导出，从 1 开始）
///   {seq2}   补零到 2 位（01, 02, ...）
///   {seq3}   补零到 3 位（001, 002, ...）
///   {date}   拍摄日期 YYYY-MM-DD（无 EXIF 时回退为空）
///   {time}   拍摄时间 HHmmss
///   {camera} 相机型号
///   {iso}    ISO 值
///   {W}      输出宽度（像素）
///   {H}      输出高度（像素）
///
/// 例：
///   "{name}_edited"      → IMG_1234_edited
///   "{date}_{seq3}"      → 2026-06-02_001
///   "{camera}_{name}"    → DC-S5_IMG_1234
class ExportTemplate {
  ExportTemplate._();

  /// 默认模板：原名 + _edited（保持历史行为）
  static const String defaultTemplate = '{name}_edited';

  /// 区分性占位符——批量导出时模板若不含这些之一，每张会撞名
  static final RegExp _distinctTokens = RegExp(
    r'\{(name|seq|seq2|seq3|time)\}',
  );

  /// 模板是否含可区分每张图的占位符
  static bool hasDistinctToken(String template) =>
      _distinctTokens.hasMatch(template);

  /// 应用模板生成文件名（不含扩展名，已清理非法字符）
  ///
  /// [seq] 为 1-based 序号，[metadata] 缺失时日期/相机/ISO 占位符回退为空串
  static String apply({
    required String template,
    required String originalName,
    required int seq,
    RawMetadata? metadata,
    int? outWidth,
    int? outHeight,
  }) {
    final ts = metadata?.timestamp;
    String dateStr = '';
    String timeStr = '';
    if (ts != null) {
      final local = ts.toLocal();
      dateStr =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      timeStr =
          '${local.hour.toString().padLeft(2, '0')}'
          '${local.minute.toString().padLeft(2, '0')}'
          '${local.second.toString().padLeft(2, '0')}';
    }

    var result = template
        .replaceAll('{name}', originalName)
        .replaceAll('{seq3}', seq.toString().padLeft(3, '0'))
        .replaceAll('{seq2}', seq.toString().padLeft(2, '0'))
        .replaceAll('{seq}', seq.toString())
        .replaceAll('{date}', dateStr)
        .replaceAll('{time}', timeStr)
        .replaceAll('{camera}', metadata?.cameraModel.trim() ?? '')
        .replaceAll('{iso}', metadata?.iso.toString() ?? '')
        .replaceAll('{W}', outWidth?.toString() ?? '')
        .replaceAll('{H}', outHeight?.toString() ?? '');

    result = sanitize(result);
    // 全部被清空（如模板只有缺失的占位符）→ 回退原名
    if (result.isEmpty) result = sanitize(originalName);
    return result;
  }

  /// 清理文件名非法字符（跨平台安全）：/ \ : * ? " < > | 及控制符 → _，
  /// 去除首尾空白与点，折叠连续下划线
  static String sanitize(String s) {
    return s
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'_{2,}'), '_') // 折叠连续下划线
        .trim()
        .replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), ''); // 去首尾点/空白
  }

  /// 去掉文件名的扩展名
  static String stripExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot <= 0 ? filename : filename.substring(0, dot);
  }

  /// 在批量导出中保证文件名唯一
  ///
  /// [base] 是模板生成的名字（不含扩展名），[extension] 不含点
  /// [used] 累积已占用的完整文件名（含扩展名，小写）；本函数会写入
  /// 撞名时追加 _1 / _2 …
  static String ensureUnique({
    required String base,
    required String extension,
    required Set<String> used,
  }) {
    String candidate = '$base.$extension';
    if (!used.contains(candidate.toLowerCase())) {
      used.add(candidate.toLowerCase());
      return candidate;
    }
    int n = 1;
    while (true) {
      candidate = '${base}_$n.$extension';
      if (!used.contains(candidate.toLowerCase())) {
        used.add(candidate.toLowerCase());
        return candidate;
      }
      n++;
    }
  }
}
