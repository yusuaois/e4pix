import '../../core/models/adjustment_params.dart';

/// 将 [AdjustmentParams] 序列化为 Lightroom 兼容的 XMP 预设文件内容。
class XmpExport {
  XmpExport._();

  static String serialize(AdjustmentParams p) {
    final buf = StringBuffer();
    buf.writeln('<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>');
    buf.writeln('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
    buf.writeln(
      '  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
    );
    buf.write(
      '    <rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"',
    );

    _attr(buf, 'Exposure2012', p.exposure);
    _attr(buf, 'Contrast2012', p.contrast);
    _attr(buf, 'Highlights2012', p.highlights);
    _attr(buf, 'Shadows2012', p.shadows);
    _attr(buf, 'Whites2012', p.whites);
    _attr(buf, 'Blacks2012', p.blacks);
    _attr(buf, 'Temperature', p.temperature.toDouble());
    _attr(buf, 'Tint', p.tint);
    _attr(buf, 'Saturation', p.saturation);
    _attr(buf, 'Vibrance', p.vibrance);
    _attr(buf, 'Sharpness', p.sharpenAmount / 100.0 * 150.0);
    _attr(buf, 'SharpenRadius', p.sharpenRadius);
    _attr(buf, 'LuminanceSmoothing', p.denoiseLuma);
    _attr(buf, 'ColorNoiseReduction', p.denoiseColor);
    if (p.grain.amount > 0.001) {
      _attr(buf, 'GrainAmount', p.grain.amount);
    }

    // HSL
    const adobeColors = [
      'Red',
      'Orange',
      'Yellow',
      'Green',
      'Aqua',
      'Blue',
      'Purple',
      'Magenta',
    ];
    final hsl = p.hsl;
    for (int i = 0; i < 8; i++) {
      if (hsl.hues[i].abs() > 0.01) {
        _attr(buf, 'HueAdjustment${adobeColors[i]}', hsl.hues[i]);
      }
      if (hsl.sats[i].abs() > 0.01) {
        _attr(buf, 'SaturationAdjustment${adobeColors[i]}', hsl.sats[i]);
      }
      if (hsl.lums[i].abs() > 0.01) {
        _attr(buf, 'LuminanceAdjustment${adobeColors[i]}', hsl.lums[i]);
      }
    }

    buf.writeln('    />');
    buf.writeln('  </rdf:RDF>');
    buf.writeln('</x:xmpmeta>');
    buf.writeln('<?xpacket end="w"?>');
    return buf.toString();
  }

  static void _attr(StringBuffer buf, String key, double value) {
    if (value.abs() < 0.005) return;
    final sign = value >= 0 ? '+' : '';
    buf.write('\n      crs:$key="$sign${value.toStringAsFixed(2)}"');
  }
}
