import 'package:e4pix/native/raw_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 注意：FFI 测试不能用 flutter test 跑，需用 dart test
  // 或在 example app 里挂一个 debug 按钮触发

  test('LibRaw version is reachable', () {
    final v = RawBridge.libRawVersion();
    print('LibRaw: $v');
    expect(v, isNotEmpty);
  });

  test('Read metadata of a sample RAW', () async {
    const path = '/path/to/sample.ARW';
    final meta = await RawBridge.readMetadata(path);
    expect(meta.cameraModel, isNotEmpty);
    print(meta);
  });

  test('Decode preview returns 16-bit pixels', () async {
    const path = '/path/to/sample.ARW';
    final img = await RawBridge.decodePreview(path);
    expect(img.bitsPerChannel, 16);
    expect(img.channels, 3);
    expect(img.pixelCount, greaterThan(1000));
    // pixels 应该是 Uint16List
    expect(img.pixels.runtimeType.toString(), contains('Uint16'));
  });
}