import 'package:flutter/foundation.dart';

/// 8 个色相通道：红 橙 黄 绿 青 蓝 紫 品红
enum HslBand { red, orange, yellow, green, cyan, blue, purple, magenta }

@immutable
class HslBands {
  /// hue/sat/lum [-100, +100]
  final List<double> hues;
  final List<double> sats;
  final List<double> lums;

  const HslBands({
    this.hues = const [0, 0, 0, 0, 0, 0, 0, 0],
    this.sats = const [0, 0, 0, 0, 0, 0, 0, 0],
    this.lums = const [0, 0, 0, 0, 0, 0, 0, 0],
  });

  static const neutral = HslBands();

  bool get isNeutral =>
      hues.every((v) => v == 0) &&
      sats.every((v) => v == 0) &&
      lums.every((v) => v == 0);

  HslBands setHue(int i, double v) =>
      HslBands(hues: _replace(hues, i, v), sats: sats, lums: lums);
  HslBands setSat(int i, double v) =>
      HslBands(hues: hues, sats: _replace(sats, i, v), lums: lums);
  HslBands setLum(int i, double v) =>
      HslBands(hues: hues, sats: sats, lums: _replace(lums, i, v));

  static List<double> _replace(List<double> src, int i, double v) =>
      List.of(src)..[i] = v;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HslBands &&
          listEquals(hues, other.hues) &&
          listEquals(sats, other.sats) &&
          listEquals(lums, other.lums);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(hues),
    Object.hashAll(sats),
    Object.hashAll(lums),
  );

  Map<String, dynamic> toJson() => {'hues': hues, 'sats': sats, 'lums': lums};

  factory HslBands.fromJson(Map<String, dynamic> j) {
    List<double> parseBand(dynamic raw) {
      final out = List<double>.filled(8, 0.0);
      if (raw is! List) return out;
      for (int i = 0; i < 8 && i < raw.length; i++) {
        final v = raw[i];
        if (v is num) out[i] = v.toDouble();
      }
      return out;
    }

    return HslBands(
      hues: parseBand(j['hues']),
      sats: parseBand(j['sats']),
      lums: parseBand(j['lums']),
    );
  }
}
