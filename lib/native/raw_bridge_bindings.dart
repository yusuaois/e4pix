// ignore_for_file: camel_case_types
import 'dart:ffi';
import 'package:ffi/ffi.dart';

// ============================================================================
// E4pixDecodeResult struct - 字段顺序必须与 C 头文件完全一致
// ============================================================================
final class E4pixDecodeResult extends Struct {
  @Int32()
  external int errorCode;

  @Array(256)
  external Array<Uint8> errorMessageBytes;

  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int channels;
  @Int32()
  external int bitsPerChannel;

  external Pointer<Uint8> pixels;

  @Size()
  external int pixelsSize;

  @Int32()
  external int orientation;
  @Int32()
  external int iso;
  @Float()
  external double shutter;
  @Float()
  external double aperture;
  @Float()
  external double focalLength;

  @Array(64)
  external Array<Uint8> cameraMakeBytes;
  @Array(64)
  external Array<Uint8> cameraModelBytes;
  @Array(128)
  external Array<Uint8> lensModelBytes;

  @Int64()
  external int timestamp;

  @Array(4)
  external Array<Float> camMul;

  @Int32()
  external int isEmbeddedThumb;
  @Int32()
  external int thumbFormat;
}

// ============================================================================
// Function signatures (C side / Dart side)
// ============================================================================
typedef DecodeC = Pointer<E4pixDecodeResult> Function(Pointer<Utf8>);
typedef DecodeDart = Pointer<E4pixDecodeResult> Function(Pointer<Utf8>);

typedef FreeC = Void Function(Pointer<E4pixDecodeResult>);
typedef FreeDart = void Function(Pointer<E4pixDecodeResult>);

typedef VersionC = Pointer<Utf8> Function();
typedef VersionDart = Pointer<Utf8> Function();

class RawBridgeBindings {
  final DynamicLibrary _lib;

  late final DecodeDart extractThumb = _lib.lookupFunction<DecodeC, DecodeDart>(
    'e4pix_extract_thumb',
  );
  late final DecodeDart decodePreviewFast = _lib
      .lookupFunction<DecodeC, DecodeDart>('e4pix_decode_preview_fast');
  late final DecodeDart decodePreview = _lib
      .lookupFunction<DecodeC, DecodeDart>('e4pix_decode_preview');
  late final DecodeDart decodeFull = _lib.lookupFunction<DecodeC, DecodeDart>(
    'e4pix_decode_full',
  );
  late final DecodeDart readMetadata = _lib.lookupFunction<DecodeC, DecodeDart>(
    'e4pix_read_metadata',
  );
  late final FreeDart freeResult = _lib.lookupFunction<FreeC, FreeDart>(
    'e4pix_free_result',
  );
  late final VersionDart version = _lib.lookupFunction<VersionC, VersionDart>(
    'e4pix_libraw_version',
  );

  RawBridgeBindings(this._lib);
}
