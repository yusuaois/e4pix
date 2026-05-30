import 'package:flutter/foundation.dart';
import 'tone_curve.dart';

@immutable
class RgbCurves {
  final ToneCurve master;
  final ToneCurve red;
  final ToneCurve green;
  final ToneCurve blue;

  const RgbCurves({
    this.master = ToneCurve.identity,
    this.red = ToneCurve.identity,
    this.green = ToneCurve.identity,
    this.blue = ToneCurve.identity,
  });

  static const identity = RgbCurves();

  bool get isIdentity =>
      master.isIdentity &&
      red.isIdentity &&
      green.isIdentity &&
      blue.isIdentity;

  RgbCurves copyWith({
    ToneCurve? master,
    ToneCurve? red,
    ToneCurve? green,
    ToneCurve? blue,
  }) => RgbCurves(
    master: master ?? this.master,
    red: red ?? this.red,
    green: green ?? this.green,
    blue: blue ?? this.blue,
  );

  Map<String, dynamic> toJson() => {
    'master': master.toJson(),
    'red': red.toJson(),
    'green': green.toJson(),
    'blue': blue.toJson(),
  };

  factory RgbCurves.fromJson(Map<String, dynamic> j) => RgbCurves(
    master: j['master'] != null
        ? ToneCurve.fromJson(j['master'])
        : ToneCurve.identity,
    red: j['red'] != null ? ToneCurve.fromJson(j['red']) : ToneCurve.identity,
    green: j['green'] != null
        ? ToneCurve.fromJson(j['green'])
        : ToneCurve.identity,
    blue: j['blue'] != null
        ? ToneCurve.fromJson(j['blue'])
        : ToneCurve.identity,
  );

  @override
  bool operator ==(Object other) =>
      other is RgbCurves &&
      other.master == master &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;
  @override
  int get hashCode => Object.hash(master, red, green, blue);
}
