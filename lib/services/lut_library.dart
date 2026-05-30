import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/lut_formats.dart';

class LutEntry {
  final String filePath;
  final String name;
  final String ext;

  const LutEntry({
    required this.filePath,
    required this.name,
    required this.ext,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LutEntry && other.filePath == filePath);

  @override
  int get hashCode => filePath.hashCode;
}

class LutLibrary {
  static Future<Directory> _getDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'luts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<LutEntry>> listAll() async {
    final dir = await _getDir();
    final files = await dir.list().toList();
    final out = files
        .whereType<File>()
        .where((f) => LutFormats.isLut(f.path))
        .map((f) {
          final e = p.extension(f.path); // ".cube" / ".vlt"
          return LutEntry(
            filePath: f.path,
            name: p.basenameWithoutExtension(f.path),
            ext: e.isEmpty ? '' : e.substring(1).toLowerCase(),
          );
        })
        .toList();
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Future<LutEntry> importFrom(String sourcePath) async {
    final dir = await _getDir();
    final filename = p.basename(sourcePath);
    var dest = p.join(dir.path, filename);

    // 同名加序号
    int i = 1;
    while (await File(dest).exists()) {
      final base = p.basenameWithoutExtension(filename);
      final ext = p.extension(filename);
      dest = p.join(dir.path, '${base}_$i$ext');
      i++;
    }

    // 复制文件
    await File(sourcePath).copy(dest);

    final e = p.extension(dest);
    return LutEntry(
      filePath: dest,
      name: p.basenameWithoutExtension(dest),
      ext: e.isEmpty ? '' : e.substring(1).toLowerCase(),
    );
  }

  static Future<void> delete(LutEntry entry) async {
    final file = File(entry.filePath);
    if (await file.exists()) await file.delete();
  }
}
