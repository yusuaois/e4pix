import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img_pkg;

import '../../native/raw_bridge.dart';

/// 图片加载：RAW LibRaw，标准图片 Flutter 原生解码
/// 产物为 8-bit sRGB ui.Image
class ImageLoader {
  ImageLoader._();

  /// 标准图片：空 metadata
  static const emptyMetadata = RawMetadata(
    orientation: 1,
    iso: 0,
    shutter: 0,
    aperture: 0,
    focalLength: 0,
    cameraMake: '',
    cameraModel: '',
    lensModel: '',
    timestamp: null,
    cameraWhiteBalance: [1, 1, 1, 1],
  );

  /// 全分辨率解码为 8-bit sRGB ui.Image
  /// 返回 (image, metadata)JPG 读 EXIF，PNG / 失败 emptyMetadata
  /// EXIF 解析在 Isolate 中执行，避免主线程阻塞
  static Future<(ui.Image, RawMetadata)> decodeFull(String path) async {
    final bytes = await File(path).readAsBytes();
    // EXIF 解析（含完整 JPEG 解码）在独立 Isolate 中运行
    final metaFuture = Isolate.run(() => _tryReadExif(bytes));
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final meta = await metaFuture ?? emptyMetadata;
    return (frame.image, meta);
  }

  /// 缩略图解码
  static Future<ui.Image> decodeThumbnail(
    String path, {
    int maxEdge = 320,
  }) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxEdge);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 从 JPG 的 EXIF 读 metadata（失败/无 EXIF 返回 null）
  static RawMetadata? _tryReadExif(Uint8List bytes) {
    try {
      final decoded = img_pkg.decodeJpg(bytes);
      if (decoded == null) return null;
      final exif = decoded.exif;

      final ifd0 = exif.imageIfd;
      final exifIfd = exif.exifIfd;

      final make = ifd0['Make']?.toString().trim() ?? '';
      final model = ifd0['Model']?.toString().trim() ?? '';
      final orientationVal = ifd0['Orientation'];
      final orientation = orientationVal?.toInt() ?? 1;

      int iso = 0;
      double shutter = 0, aperture = 0, focal = 0;
      String lens = '';
      DateTime? ts;

      final isoVal = exifIfd[0x8827]; // ISOSpeedRatings
      if (isoVal != null) iso = isoVal.toInt();
      final expVal = exifIfd[0x829A]; // ExposureTime
      if (expVal != null) shutter = expVal.toDouble();
      final fnumVal = exifIfd[0x829D]; // FNumber
      if (fnumVal != null) aperture = fnumVal.toDouble();
      final focalVal = exifIfd[0x920A]; // FocalLength
      if (focalVal != null) focal = focalVal.toDouble();
      lens = exifIfd[0xA434]?.toString().trim() ?? ''; // LensModel
      final dtVal = exifIfd[0x9003]?.toString(); // DateTimeOriginal
      if (dtVal != null) ts = _parseExifDate(dtVal);

      // 全部字段为空/0 → 视为无有效 EXIF
      if (make.isEmpty &&
          model.isEmpty &&
          iso == 0 &&
          shutter == 0 &&
          aperture == 0 &&
          focal == 0 &&
          ts == null) {
        return null;
      }

      return RawMetadata(
        orientation: orientation,
        iso: iso,
        shutter: shutter,
        aperture: aperture,
        focalLength: focal,
        cameraMake: make,
        cameraModel: model,
        lensModel: lens,
        timestamp: ts,
        cameraWhiteBalance: const [1, 1, 1, 1], // 标准图无 RAW 白平衡系数
      );
    } catch (e) {
      debugPrint('[ImageLoader] EXIF parse failed: $e');
      return null;
    }
  }

  /// "YYYY:MM:DD HH:MM:SS" → DateTime
  static DateTime? _parseExifDate(String s) {
    try {
      final parts = s.trim().split(' ');
      if (parts.length != 2) return null;
      final d = parts[0].split(':');
      final t = parts[1].split(':');
      if (d.length != 3 || t.length != 3) return null;
      return DateTime(
        int.parse(d[0]),
        int.parse(d[1]),
        int.parse(d[2]),
        int.parse(t[0]),
        int.parse(t[1]),
        int.parse(t[2]),
      );
    } catch (_) {
      return null;
    }
  }
}
