import 'package:easy_localization/easy_localization.dart';
import 'package:xml/xml.dart';

import '../../core/models/adjustment_params.dart';
import '../../core/models/hsl_bands.dart';
import '../../core/models/rgb_curves.dart';
import '../../core/models/tone_curve.dart';

/// XMP（Adobe Camera Raw / Lightroom 边车）导入
///
/// 解析 crs: 命名空间下的编辑参数，映射到 [AdjustmentParams]
///
/// 重要限制：仅搬运数值，**不保证渲染结果与 Camera Raw 一致**——Adobe 的
/// 处理管线（ProcessVersion、色彩科学）与 e4pix 的 shader 管线不同，同一数值的视觉效果会有差异
/// 导入后通常需要微调
///
/// 第一步仅映射基础调整（曝光/对比度/影调/白平衡/饱和/锐化/降噪）
/// HSL 与曲线在第二步加入
class XmpImport {
  XmpImport._();

  /// 解析 XMP 文本，把识别到的字段覆盖到 [base] 上（未识别字段保留 base 的值）
  ///
  /// 返回 (新参数, 命中的字段名列表)，字段名列表可用于 UI 提示导入了哪些
  /// 解析失败抛 [FormatException]
  static (AdjustmentParams, List<String>) parse(
    String xmpContent,
    AdjustmentParams base,
  ) {
    final cleaned = _sanitizeXmp(xmpContent);
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(cleaned);
    } on XmlException catch (e) {
      throw FormatException(tr('xmpImportFailed', args: [e.message]));
    }
    final values = _extractCrsValues(doc);
    if (values.isEmpty) {
      throw FormatException(tr('xmpNoFields'));
    }

    final hit = <String>[];
    var p = base;

    // 曝光 Exposure2012（EV，-5..+5）
    final exposure = _d(values, 'Exposure2012');
    if (exposure != null) {
      p = p.copyWith(exposure: exposure.clamp(-5.0, 5.0));
      hit.add(tr('exposure'));
    }

    // 对比度 Contrast2012（-100..100）
    final contrast = _d(values, 'Contrast2012');
    if (contrast != null) {
      p = p.copyWith(contrast: contrast.clamp(-100.0, 100.0));
      hit.add(tr('contrast'));
    }

    // 高光 Highlights2012
    final highlights = _d(values, 'Highlights2012');
    if (highlights != null) {
      p = p.copyWith(highlights: highlights.clamp(-100.0, 100.0));
      hit.add(tr('highlight'));
    }

    // 阴影 Shadows2012
    final shadows = _d(values, 'Shadows2012');
    if (shadows != null) {
      p = p.copyWith(shadows: shadows.clamp(-100.0, 100.0));
      hit.add(tr('shadow'));
    }

    // 白色 Whites2012
    final whites = _d(values, 'Whites2012');
    if (whites != null) {
      p = p.copyWith(whites: whites.clamp(-100.0, 100.0));
      hit.add(tr('white'));
    }

    // 黑色 Blacks2012
    final blacks = _d(values, 'Blacks2012');
    if (blacks != null) {
      p = p.copyWith(blacks: blacks.clamp(-100.0, 100.0));
      hit.add(tr('black'));
    }

    // 色温 Temperature（开尔文）
    final temp = _d(values, 'Temperature');
    if (temp != null && temp >= 1000 && temp <= 50000) {
      p = p.copyWith(temperature: temp.round().clamp(2000, 12000));
      hit.add(tr('whiteBalance'));
    }

    // 色调 Tint
    final tint = _d(values, 'Tint');
    if (tint != null) {
      p = p.copyWith(tint: tint.clamp(-100.0, 100.0));
      hit.add(tr('tint'));
    }

    // 饱和度 Saturation
    final saturation = _d(values, 'Saturation');
    if (saturation != null) {
      p = p.copyWith(saturation: saturation.clamp(-100.0, 100.0));
      hit.add(tr('saturation'));
    }

    // 自然饱和度 Vibrance
    final vibrance = _d(values, 'Vibrance');
    if (vibrance != null) {
      p = p.copyWith(vibrance: vibrance.clamp(-100.0, 100.0));
      hit.add(tr('vibrance'));
    }

    // 锐化 Sharpness（Adobe 0..150）→ e4pix sharpenAmount（0..100）
    final sharpness = _d(values, 'Sharpness');
    if (sharpness != null) {
      p = p.copyWith(
        sharpenAmount: (sharpness / 150.0 * 100.0).clamp(0.0, 100.0),
      );
      hit.add(tr('sharpenAmount'));
    }

    // 锐化半径 SharpenRadius（Adobe 0.5..3.0，与 e4pix 一致）
    final sharpenRadius = _d(values, 'SharpenRadius');
    if (sharpenRadius != null) {
      p = p.copyWith(sharpenRadius: sharpenRadius.clamp(0.5, 3.0));
      hit.add(tr('sharpenRadius'));
    }

    // 明度降噪 LuminanceSmoothing（0..100）
    final lumaNr = _d(values, 'LuminanceSmoothing');
    if (lumaNr != null) {
      p = p.copyWith(denoiseLuma: lumaNr.clamp(0.0, 100.0));
      hit.add(tr('denoiseLuma'));
    }

    // 颜色降噪 ColorNoiseReduction（0..100）
    final colorNr = _d(values, 'ColorNoiseReduction');
    if (colorNr != null) {
      p = p.copyWith(denoiseColor: colorNr.clamp(0.0, 100.0));
      hit.add(tr('denoiseColor'));
    }

    final hues = List<double>.from(base.hsl.hues);
    final sats = List<double>.from(base.hsl.sats);
    final lums = List<double>.from(base.hsl.lums);
    bool hslHit = false;
    for (int i = 0; i < HslBand.values.length; i++) {
      // HSL（红橙黄绿青蓝紫品红）
      final band = HslBand.values[i];
      final adobeColor = band.adobeName;

      final h = _d(values, 'HueAdjustment$adobeColor');
      final s = _d(values, 'SaturationAdjustment$adobeColor');
      final l = _d(values, 'LuminanceAdjustment$adobeColor');
      if (h != null) {
        hues[i] = h.clamp(-100.0, 100.0);
        hslHit = true;
      }
      if (s != null) {
        sats[i] = s.clamp(-100.0, 100.0);
        hslHit = true;
      }
      if (l != null) {
        lums[i] = l.clamp(-100.0, 100.0);
        hslHit = true;
      }
    }
    if (hslHit) {
      p = p.copyWith(
        hsl: HslBands(hues: hues, sats: sats, lums: lums),
      );
      hit.add('HSL');
    }

    // 曲线 ToneCurvePV2012（主 + RGB 分通道）
    final curveHit = _parseCurves(doc, base);
    if (curveHit != null) {
      p = p.copyWith(curves: curveHit);
      hit.add(tr('curve'));
    }

    // 颗粒 GrainAmount
    final grain = _d(values, 'GrainAmount');
    if (grain != null) {
      p = p.copyWith(
        grain: base.grain.copyWith(amount: grain.clamp(0.0, 100.0)),
      );
      hit.add(tr('grain'));
    }

    return (p, hit);
  }

  /// 提取所有 crs: 命名空间字段，返回 {字段名(去前缀): 字符串值}
  ///
  /// 兼容两种写法：
  /// 1. 作为 rdf:Description 的 XML 属性：crs:Exposure2012="+1.00"
  /// 2. 作为子元素：<crs:Exposure2012>+1.00<crs:Exposure2012>
  static Map<String, String> _extractCrsValues(XmlDocument doc) {
    final out = <String, String>{};

    for (final el in doc.descendants.whereType<XmlElement>()) {
      // 属性形式
      for (final attr in el.attributes) {
        final name = attr.name;
        if (name.prefix == 'crs') {
          out[name.local] = attr.value.trim();
        }
      }
      // 元素形式：<crs:Foo>value</crs:Foo>（仅取纯文本、无子元素的）
      if (el.name.prefix == 'crs') {
        final childElements = el.children.whereType<XmlElement>();
        if (childElements.isEmpty) {
          final text = el.innerText.trim();
          if (text.isNotEmpty) {
            out.putIfAbsent(el.name.local, () => text);
          }
        }
      }
    }
    return out;
  }

  /// 取数值字段（Adobe 常带正号如 "+1.00"，XmlAttribute 已去引号）
  static double? _d(Map<String, String> values, String key) {
    final raw = values[key];
    if (raw == null) return null;
    return double.tryParse(raw.replaceAll('+', '').trim());
  }

  /// 清理 XMP 文本，提高 XmlDocument.parse 的成功率：
  /// - 去除 UTF-8 BOM 和前后空白
  /// - 若被 <?xpacket?> 包裹，裁出 x:xmpmeta…x:xmpmeta 主体
  ///   （xpacket 处理指令本身合法，但去掉更稳，避免某些尾部填充空白问题）
  static String _sanitizeXmp(String s) {
    var out = s;
    // 去 BOM
    if (out.isNotEmpty && out.codeUnitAt(0) == 0xFEFF) {
      out = out.substring(1);
    }
    out = out.trim();

    // 裁出 xmpmeta 主体（若存在）
    final start = out.indexOf('<x:xmpmeta');
    final endTag = '</x:xmpmeta>';
    final endIdx = out.lastIndexOf(endTag);
    if (start >= 0 && endIdx > start) {
      out = out.substring(start, endIdx + endTag.length);
    } else {
      // 没有 xmpmeta，尝试裁 rdf:RDF（部分边车直接以 RDF 为根）
      final rdfStart = out.indexOf('<rdf:RDF');
      final rdfEnd = out.lastIndexOf('</rdf:RDF>');
      if (rdfStart >= 0 && rdfEnd > rdfStart) {
        out = out.substring(rdfStart, rdfEnd + '</rdf:RDF>'.length);
      }
    }
    return out;
  }

  /// 解析 ToneCurvePV2012 系列，返回新的 RgbCurves（无曲线则 null）
  static RgbCurves? _parseCurves(XmlDocument doc, AdjustmentParams base) {
    final master = _parseOneCurve(doc, 'ToneCurvePV2012');
    final red = _parseOneCurve(doc, 'ToneCurvePV2012Red');
    final green = _parseOneCurve(doc, 'ToneCurvePV2012Green');
    final blue = _parseOneCurve(doc, 'ToneCurvePV2012Blue');
    if (master == null && red == null && green == null && blue == null) {
      return null;
    }
    return base.curves.copyWith(
      master: master,
      red: red,
      green: green,
      blue: blue,
    );
  }

  /// 解析单条曲线元素 → ToneCurve（归一化点），无或为线性默认则 null
  static ToneCurve? _parseOneCurve(XmlDocument doc, String tagLocal) {
    // 找 <crs:tagLocal> 元素
    XmlElement? curveEl;
    for (final el in doc.descendants.whereType<XmlElement>()) {
      if (el.name.prefix == 'crs' && el.name.local == tagLocal) {
        curveEl = el;
        break;
      }
    }
    if (curveEl == null) return null;

    // 读 rdf:Seq / rdf:li
    final points = <Offset2>[];
    for (final li in curveEl.descendants.whereType<XmlElement>()) {
      if (li.name.local == 'li') {
        final text = li.innerText.trim(); // "128, 140"
        final parts = text.split(',');
        if (parts.length == 2) {
          final inV = double.tryParse(parts[0].trim());
          final outV = double.tryParse(parts[1].trim());
          if (inV != null && outV != null) {
            points.add(
              Offset2(
                (inV / 255.0).clamp(0.0, 1.0),
                (outV / 255.0).clamp(0.0, 1.0),
              ),
            );
          }
        }
      }
    }
    if (points.length < 2) return null;
    // 排序确保 x 递增
    points.sort((a, b) => a.x.compareTo(b.x));
    // 若就是线性（首尾对角且仅两点），视为无调整
    if (points.length == 2 &&
        (points[0].x - 0).abs() < 0.01 &&
        (points[0].y - 0).abs() < 0.01 &&
        (points[1].x - 1).abs() < 0.01 &&
        (points[1].y - 1).abs() < 0.01) {
      return null;
    }
    return ToneCurve(points);
  }
}
