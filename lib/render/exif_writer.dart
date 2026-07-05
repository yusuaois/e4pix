import 'package:image/image.dart' as img_pkg;
import '../native/raw_bridge.dart';

/// 把 RAW 拍摄信息写入 image 包的 Image 的 EXIF（JPEG）
void writeExifToImage(img_pkg.Image image, RawMetadata m) {
  final ifd0 = image.exif.imageIfd;
  final exifIfd = image.exif.exifIfd;

  // ── IFD0（主）──
  if (m.cameraMake.trim().isNotEmpty) {
    ifd0[0x010F] = img_pkg.IfdValueAscii(m.cameraMake.trim());
  }
  if (m.cameraModel.trim().isNotEmpty) {
    ifd0[0x0110] = img_pkg.IfdValueAscii(m.cameraModel.trim());
  }
  ifd0[0x0112] = img_pkg.IfdValueShort(1);
  ifd0[0x0131] = img_pkg.IfdValueAscii('e4pix');

  // ── EXIF 子 IFD ──
  if (m.iso > 0) {
    exifIfd[0x8827] = img_pkg.IfdValueShort(m.iso);
  }
  if (m.shutter > 0) {
    if (m.shutter >= 1.0) {
      exifIfd[0x829A] = img_pkg.IfdValueRational(
        (m.shutter * 1000).round(),
        1000,
      );
    } else {
      exifIfd[0x829A] = img_pkg.IfdValueRational(1, (1.0 / m.shutter).round());
    }
  }
  if (m.aperture > 0) {
    exifIfd[0x829D] = img_pkg.IfdValueRational((m.aperture * 100).round(), 100);
  }
  if (m.focalLength > 0) {
    exifIfd[0x920A] = img_pkg.IfdValueRational(
      (m.focalLength * 100).round(),
      100,
    );
  }
  if (m.lensModel.trim().isNotEmpty) {
    exifIfd[0xA434] = img_pkg.IfdValueAscii(m.lensModel.trim());
  }

  // ── 拍摄日期 ──
  final ts = m.timestamp;
  if (ts != null) {
    final local = ts.toLocal();
    final s =
        '${local.year.toString().padLeft(4, '0')}:'
        '${local.month.toString().padLeft(2, '0')}:'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
    exifIfd[0x9003] = img_pkg.IfdValueAscii(s);
    exifIfd[0x9004] = img_pkg.IfdValueAscii(s);
    ifd0[0x0132] = img_pkg.IfdValueAscii(s);
  }
}
