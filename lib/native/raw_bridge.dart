import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'raw_bridge_bindings.dart';

/// 解码后图像
class RawDecodedImage {
  final int width;
  final int height;
  final int channels;
  final int bitsPerChannel;

  /// 像素数据
  final TypedData pixels;

  final RawMetadata metadata;

  final bool isJpegEncoded;

  const RawDecodedImage({
    required this.width,
    required this.height,
    required this.channels,
    required this.bitsPerChannel,
    required this.pixels,
    required this.metadata,
    this.isJpegEncoded = false,
  });

  int get pixelCount => width * height;
}

class RawMetadata {
  final int orientation; // EXIF 1-8
  final int iso;
  final double shutter; // seconds
  final double aperture; // f-number
  final double focalLength; // mm
  final String cameraMake;
  final String cameraModel;
  final String lensModel;
  final DateTime? timestamp;
  final List<double> cameraWhiteBalance; // [R, G1, B, G2]

  const RawMetadata({
    required this.orientation,
    required this.iso,
    required this.shutter,
    required this.aperture,
    required this.focalLength,
    required this.cameraMake,
    required this.cameraModel,
    required this.lensModel,
    required this.timestamp,
    required this.cameraWhiteBalance,
  });

  String get shutterDisplay {
    if (shutter <= 0) return '—';
    if (shutter >= 1) return '${shutter.toStringAsFixed(1)}s';
    return '1/${(1 / shutter).round()}';
  }

  @override
  String toString() =>
      '$cameraMake $cameraModel | ISO $iso | $shutterDisplay | f/$aperture | ${focalLength.toStringAsFixed(0)}mm';
}

class RawDecodeException implements Exception {
  final int code;
  final String message;
  RawDecodeException(this.code, this.message);
  @override
  String toString() => 'RawDecodeException($code): $message';
}

class RawBridge {
  RawBridge._();

  static RawBridgeBindings? _bindings;

  static RawBridgeBindings _ensureLoaded() {
    if (_bindings != null) return _bindings!;
    _bindings = RawBridgeBindings(_openLibrary());
    return _bindings!;
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('e4pix_raw.dll');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('e4pix_raw.framework/e4pix_raw');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libe4pix_raw.so');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libe4pix_raw.so');
    }
    throw UnsupportedError(
      'Platform ${Platform.operatingSystem} not supported',
    );
  }

  static String libRawVersion() {
    final b = _ensureLoaded();
    return b.version().toDartString();
  }

  /// 提取内嵌缩略图
  static Future<RawDecodedImage> extractThumbnail(String path) {
    return Isolate.run(() => _extractThumbSync(path));
  }

  /// 快速预览
  static Future<RawDecodedImage> decodePreviewFast(String path) {
    return Isolate.run(() => _decodeSync(path, _DecodeMode.previewFast));
  }

  /// 解码预览
  static Future<RawDecodedImage> decodePreview(String path) {
    return Isolate.run(() => _decodeSync(path, _DecodeMode.preview));
  }

  /// 解码全分辨率
  static Future<RawDecodedImage> decodeFull(String path) {
    return Isolate.run(() => _decodeSync(path, _DecodeMode.full));
  }

  /// 仅元数据
  static Future<RawMetadata> readMetadata(String path) async {
    final image = await Isolate.run(
      () => _decodeSync(path, _DecodeMode.metadata),
    );
    return image.metadata;
  }

  static RawDecodedImage _extractThumbSync(String path) {
    final b = _ensureLoaded();
    final pathPtr = path.toNativeUtf8();
    Pointer<E4pixDecodeResult>? resultPtr;
    try {
      resultPtr = b.extractThumb(pathPtr);
      return _convertResult(resultPtr.ref, isThumb: true);
    } finally {
      if (resultPtr != null) b.freeResult(resultPtr);
      malloc.free(pathPtr);
    }
  }

  static RawDecodedImage _decodeSync(String path, _DecodeMode mode) {
    final b = _ensureLoaded();
    final pathPtr = path.toNativeUtf8();
    Pointer<E4pixDecodeResult>? resultPtr;
    try {
      resultPtr = switch (mode) {
        _DecodeMode.previewFast => b.decodePreviewFast(pathPtr),
        _DecodeMode.preview => b.decodePreview(pathPtr),
        _DecodeMode.full => b.decodeFull(pathPtr),
        _DecodeMode.metadata => b.readMetadata(pathPtr),
      };
      return _convertResult(
        resultPtr.ref,
        isMetadataOnly: mode == _DecodeMode.metadata,
      );
    } finally {
      if (resultPtr != null) b.freeResult(resultPtr);
      malloc.free(pathPtr);
    }
  }

  static RawDecodedImage _convertResult(
    E4pixDecodeResult r, {
    bool isThumb = false,
    bool isMetadataOnly = false,
  }) {
    if (r.errorCode != 0) {
      throw RawDecodeException(
        r.errorCode,
        _readFixedCString(r.errorMessageBytes, 256),
      );
    }

    final TypedData pixels;
    if (isMetadataOnly) {
      pixels = Uint8List(0);
    } else if (r.bitsPerChannel == 16) {
      // 拷贝Uint16List
      final ptr16 = r.pixels.cast<Uint16>();
      final count = r.pixelsSize ~/ 2;
      pixels = Uint16List.fromList(ptr16.asTypedList(count));
    } else {
      // 拷贝Uint8List
      pixels = Uint8List.fromList(r.pixels.asTypedList(r.pixelsSize));
    }

    final metadata = RawMetadata(
      orientation: r.orientation,
      iso: r.iso,
      shutter: r.shutter,
      aperture: r.aperture,
      focalLength: r.focalLength,
      cameraMake: _readFixedCString(r.cameraMakeBytes, 64),
      cameraModel: _readFixedCString(r.cameraModelBytes, 64),
      lensModel: _readFixedCString(r.lensModelBytes, 128),
      timestamp: r.timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(r.timestamp * 1000, isUtc: true)
          : null,
      cameraWhiteBalance: List.generate(4, (i) => r.camMul[i]),
    );

    return RawDecodedImage(
      width: r.width,
      height: r.height,
      channels: r.channels,
      bitsPerChannel: r.bitsPerChannel,
      pixels: pixels,
      metadata: metadata,
      isJpegEncoded: isThumb && r.thumbFormat == 1,
    );
  }

  static String _readFixedCString(Array<Uint8> arr, int maxLen) {
    final bytes = <int>[];
    for (int i = 0; i < maxLen; i++) {
      final b = arr[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return String.fromCharCodes(bytes);
  }
}

enum _DecodeMode { previewFast, preview, full, metadata }
