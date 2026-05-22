import 'package:e4pix/native/raw_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LibRaw version is reachable', () {
    final v = RawBridge.libRawVersion();
    expect(v, isNotEmpty);
  });

  test('Read metadata of a sample RAW', () async {
    const path = '/path/to/sample.ARW';
    final meta = await RawBridge.readMetadata(path);
    expect(meta.cameraModel, isNotEmpty);
  });

  test('Decode preview returns 16-bit pixels', () async {
    const path = '/path/to/sample.ARW';
    final img = await RawBridge.decodePreview(path);
    expect(img.bitsPerChannel, 16);
    expect(img.channels, 3);
    expect(img.pixelCount, greaterThan(1000));
    expect(img.pixels.runtimeType.toString(), contains('Uint16'));
  });
}