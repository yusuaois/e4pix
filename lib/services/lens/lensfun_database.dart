import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../app/assets_init.dart';

/// Lensfun XML 解析结果 —— 单组校正系数
class LensfunCalibration {
  final double distortionA;
  final double distortionB;
  final double distortionC;
  final double tcaBr;
  final double tcaVr;
  final double tcaBb;
  final double tcaVb;
  final double vignettingK1;
  final double vignettingK2;
  final double vignettingK3;

  const LensfunCalibration({
    required this.distortionA,
    required this.distortionB,
    required this.distortionC,
    required this.tcaBr,
    required this.tcaVr,
    required this.tcaBb,
    required this.tcaVb,
    required this.vignettingK1,
    required this.vignettingK2,
    required this.vignettingK3,
  });

  static const empty = LensfunCalibration(
    distortionA: 0,
    distortionB: 0,
    distortionC: 0,
    tcaBr: 0,
    tcaVr: 1,
    tcaBb: 0,
    tcaVb: 1,
    vignettingK1: 0,
    vignettingK2: 0,
    vignettingK3: 0,
  );
}

class _LensEntry {
  final String cameraMaker;
  final String cameraModel;
  final String lensMaker;
  final String lensModel;
  final double focal;
  final double focalMin;
  final double focalMax;
  final double minAperture;
  final List<_DistortionEntry> distortions;
  final List<_TcaEntry> tcas;
  final List<_VignettingEntry> vignettings;
  final double cropfactor;

  _LensEntry({
    required this.cameraMaker,
    required this.cameraModel,
    required this.lensMaker,
    required this.lensModel,
    required this.focal,
    required this.focalMin,
    required this.focalMax,
    required this.minAperture,
    required this.cropfactor,
    required this.distortions,
    required this.tcas,
    required this.vignettings,
  });
}

class _DistortionEntry {
  final double focal;
  final double a, b, c;
  _DistortionEntry(this.focal, this.a, this.b, this.c);
}

class _TcaEntry {
  final double focal;
  final double br, vr, bb, vb;
  _TcaEntry(this.focal, this.br, this.vr, this.bb, this.vb);
}

class _VignettingEntry {
  final double focal;
  final double aperture;
  final double k1, k2, k3;
  _VignettingEntry(this.focal, this.aperture, this.k1, this.k2, this.k3);
}

class _CameraInfo {
  final String maker;
  final String model;
  final double cropfactor;
  _CameraInfo(this.maker, this.model, this.cropfactor);
}

/// 解析结果
class _ParseResult {
  final Map<String, _CameraInfo> cameras;
  final Map<String, List<String>> camByMount;
  final Map<String, List<_LensEntry>> byCameraLens;
  final Map<String, List<_LensEntry>> byLensModel;
  _ParseResult(
    this.cameras,
    this.camByMount,
    this.byCameraLens,
    this.byLensModel,
  );
}

String _text(XmlElement parent, String tag) {
  final e = parent.findAllElements(tag).firstOrNull;
  return e?.innerText.trim() ?? '';
}

double _attrDouble(
  XmlElement parent,
  String tag,
  String attr,
  double fallback,
) {
  final e = parent.findAllElements(tag).firstOrNull;
  if (e == null) return fallback;
  return double.tryParse(e.getAttribute(attr) ?? '') ?? fallback;
}

double _doubleOr(XmlElement parent, String tag, double fallback) {
  final e = parent.findAllElements(tag).firstOrNull;
  if (e == null) return fallback;
  return double.tryParse(e.innerText.trim()) ?? fallback;
}

double _attr(XmlElement el, String attr, double fallback) {
  return double.tryParse(el.getAttribute(attr) ?? '') ?? fallback;
}

// 解析入口
_ParseResult _parseAllXml(List<String> xmlStrings) {
  final cameras = <String, _CameraInfo>{};
  final camByMount = <String, List<String>>{};
  final byCameraLens = <String, List<_LensEntry>>{};
  final byLensModel = <String, List<_LensEntry>>{};

  final docs = <XmlDocument>[];

  // 阶段 1：解析 DOM 并提取相机
  for (final xml in xmlStrings) {
    try {
      final doc = XmlDocument.parse(xml);
      docs.add(doc);

      for (final cam in doc.findAllElements('camera')) {
        final maker = _text(cam, 'maker');
        final model = _text(cam, 'model');
        final mount = _text(cam, 'mount');
        final crop = _doubleOr(cam, 'cropfactor', 1.0);
        if (maker.isEmpty || model.isEmpty) continue;
        final key = '$maker|$model';
        cameras[key] = _CameraInfo(maker, model, crop);
        if (mount.isNotEmpty) {
          camByMount.putIfAbsent(mount.toLowerCase(), () => []).add(key);
        }
      }
    } catch (e) {
      debugPrint('[LensfunDB] Load failed: $e');
    }
  }

  // 阶段 2：复用 DOM 提取镜头
  for (final doc in docs) {
    for (final node in doc.rootElement.children.whereType<XmlElement>()) {
      if (node.name.local != 'lens') continue;

      final lMaker = _text(node, 'maker');
      final lModel = _text(node, 'model');
      final mount = _text(node, 'mount');
      final focalMin = _attrDouble(node, 'focal', 'min', 0);
      final focalMax = _attrDouble(node, 'focal', 'max', focalMin);
      final focalRaw = focalMin > 0 ? focalMin : focalMax;
      final apMin = _attrDouble(node, 'aperture', 'min', 0);
      final apMax = _attrDouble(node, 'aperture', 'max', 0);
      final crop = _doubleOr(node, 'cropfactor', 1.0);

      final candidates = camByMount[mount.toLowerCase()];
      if (candidates == null || candidates.isEmpty) continue;

      for (final cKey in candidates) {
        final cam = cameras[cKey]!;

        final dists = <_DistortionEntry>[];
        final tcas = <_TcaEntry>[];
        final vigns = <_VignettingEntry>[];

        for (final cal in node.findAllElements('calibration')) {
          for (final d in cal.findAllElements('distortion')) {
            if (d.getAttribute('model') != 'ptlens') continue;
            dists.add(
              _DistortionEntry(
                _attr(d, 'focal', focalRaw),
                _attr(d, 'a', 0),
                _attr(d, 'b', 0),
                _attr(d, 'c', 0),
              ),
            );
          }
          for (final t in cal.findAllElements('tca')) {
            if (t.getAttribute('model') != 'poly3') continue;
            tcas.add(
              _TcaEntry(
                _attr(t, 'focal', focalRaw),
                _attr(t, 'br', 0),
                _attr(t, 'vr', 1),
                _attr(t, 'bb', 0),
                _attr(t, 'vb', 1),
              ),
            );
          }
          for (final v in cal.findAllElements('vignetting')) {
            vigns.add(
              _VignettingEntry(
                _attr(v, 'focal', focalRaw),
                _attr(v, 'aperture', apMin),
                _attr(v, 'k1', 0),
                _attr(v, 'k2', 0),
                _attr(v, 'k3', 0),
              ),
            );
          }
        }

        if (dists.isEmpty && tcas.isEmpty && vigns.isEmpty) continue;

        final entry = _LensEntry(
          cameraMaker: cam.maker,
          cameraModel: cam.model,
          lensMaker: lMaker,
          lensModel: lModel,
          focal: focalRaw,
          focalMin: focalMin,
          focalMax: focalMax,
          minAperture: apMin > 0 ? apMin : apMax,
          cropfactor: crop > 0 ? crop : cam.cropfactor,
          distortions: dists,
          tcas: tcas,
          vignettings: vigns,
        );

        final clKey = '${cam.maker}|${cam.model}\x00$lModel'.toLowerCase();
        byCameraLens.putIfAbsent(clKey, () => []).add(entry);
        byLensModel.putIfAbsent(lModel.toLowerCase(), () => []).add(entry);
      }
    }
  }

  return _ParseResult(cameras, camByMount, byCameraLens, byLensModel);
}

/// Lensfun XML 数据库解析与查表
class LensfunDatabase {
  LensfunDatabase._();
  static final instance = LensfunDatabase._();
  bool _loaded = false;

  final _cameras = <String, _CameraInfo>{};
  final _camByMount = <String, List<String>>{};
  final Map<String, List<_LensEntry>> _byCameraLens = {};
  final Map<String, List<_LensEntry>> _byLensModel = {};

  // 加载
  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final dir = await _lensfunDir();

    // 首次启动/升级时将 assets/lensfun/data/db/*.xml 释放到可写目录
    await AssetsInit.releaseIfNeeded(
      namespace: 'lensfun',
      assetPrefix: 'assets/lensfun/data/db/',
      fileExtension: '.xml',
      targetDirPath: dir,
    );

    await _loadFromDir(dir);
    _loaded = true;
  }

  Future<String> _lensfunDir() async {
    final base = await getApplicationSupportDirectory();
    return p.join(base.path, 'lensfun');
  }

  Future<void> _loadFromDir(String dir) async {
    final xmlStrings = <String>[];
    final lensfunDir = Directory(dir);
    if (await lensfunDir.exists()) {
      final files = lensfunDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.xml'),
      );
      for (final file in files) {
        try {
          xmlStrings.add(await file.readAsString());
        } catch (e) {
          debugPrint('[LensfunDB] Failed to load ${file.path}: $e');
        }
      }
    }

    if (xmlStrings.isEmpty) {
      debugPrint('[LensfunDB] No XML files found in $dir');
      return;
    }

    // 后台解析
    final result = await Isolate.run(() => _parseAllXml(xmlStrings));

    _cameras.addAll(result.cameras);
    _camByMount.addAll(result.camByMount);
    _byCameraLens.addAll(result.byCameraLens);
    _byLensModel.addAll(result.byLensModel);
  }

  // ── 查表 ────────────────────────────────────────────────────────

  LensfunCalibration? lookup({
    required String cameraMake,
    required String cameraModel,
    required String lensModel,
    double focalLength = 0,
    double aperture = 0,
  }) {
    if (!_loaded) return null;

    // 1) 大小写不敏感精确匹配
    final key = '$cameraMake|$cameraModel\x00$lensModel'.toLowerCase();
    if (_byCameraLens.containsKey(key)) {
      return _selectBest(_byCameraLens[key]!, focalLength, aperture);
    }

    // 2) token 模糊匹配（≥2 token 重叠，限同一相机型号）
    final normLens = _normalize(lensModel);
    final candidates = <_LensEntry>[];
    for (final e in _byCameraLens.entries) {
      final dbNorm = _normalize(e.key.split('\x00').last);
      if (_tokenOverlap(normLens, dbNorm) >= 2) {
        candidates.addAll(
          e.value.where(
            (en) => en.cameraModel.toLowerCase() == cameraModel.toLowerCase(),
          ),
        );
      }
    }
    if (candidates.isNotEmpty) {
      return _selectBest(candidates, focalLength, aperture);
    }

    // 3) 纯镜头名 token 匹配
    final byModel = <_LensEntry>[];
    for (final e in _byLensModel.entries) {
      if (_tokenOverlap(normLens, _normalize(e.key)) >= 2) {
        byModel.addAll(e.value);
      }
    }
    if (byModel.isNotEmpty) {
      return _selectBest(byModel, focalLength, aperture);
    }

    return null;
  }

  LensfunCalibration? _selectBest(
    List<_LensEntry> entries,
    double focal,
    double aperture,
  ) {
    _LensEntry? best;
    double bestDist = double.infinity;
    for (final e in entries) {
      final f = e.focal > 0 ? e.focal : ((e.focalMin + e.focalMax) / 2);
      final d = (f - focal).abs();
      if (d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    if (best == null) return null;

    _DistortionEntry? bestD;
    double bestDd = double.infinity;
    for (final d in best.distortions) {
      final dd = (d.focal - focal).abs();
      if (dd < bestDd) {
        bestDd = dd;
        bestD = d;
      }
    }

    _TcaEntry? bestT;
    double bestTd = double.infinity;
    for (final t in best.tcas) {
      final td = (t.focal - focal).abs();
      if (td < bestTd) {
        bestTd = td;
        bestT = t;
      }
    }

    _VignettingEntry? bestV;
    double bestVd = double.infinity;
    for (final v in best.vignettings) {
      if (v.aperture <= 0) continue;
      final vd = (v.aperture - aperture).abs();
      if (vd < bestVd) {
        bestVd = vd;
        bestV = v;
      }
    }

    return LensfunCalibration(
      distortionA: bestD?.a ?? 0,
      distortionB: bestD?.b ?? 0,
      distortionC: bestD?.c ?? 0,
      tcaBr: bestT?.br ?? 0,
      tcaVr: bestT?.vr ?? 1,
      tcaBb: bestT?.bb ?? 0,
      tcaVb: bestT?.vb ?? 1,
      vignettingK1: bestV?.k1 ?? 0,
      vignettingK2: bestV?.k2 ?? 0,
      vignettingK3: bestV?.k3 ?? 0,
    );
  }

  // ── 工具 ────────────────────────────────────────────────────────

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[/\-\.\,]'), ' ');

  int _tokenOverlap(String a, String b) {
    final ta = a.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
    final tb = b.split(RegExp(r'\s+')).where((t) => t.length > 1).toSet();
    return ta.intersection(tb).length;
  }
}
