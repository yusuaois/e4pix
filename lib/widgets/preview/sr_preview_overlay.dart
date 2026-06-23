import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../services/sr/sr_service.dart';

/// 超分辨率局部预览覆盖层
///
/// 显示在预览区右下角，点击可切换预览焦点位置
/// 直接使用源图进行超分推理，不依赖渲染结果
class SrPreviewOverlay extends ConsumerStatefulWidget {
  final Size displaySize;
  final ui.Image sourceImage;

  const SrPreviewOverlay({
    super.key,
    required this.displaySize,
    required this.sourceImage,
  });

  @override
  ConsumerState<SrPreviewOverlay> createState() => _SrPreviewOverlayState();
}

class _SrPreviewOverlayState extends ConsumerState<SrPreviewOverlay> {
  static const double _previewSize = 200;
  static const int _cropSize = 128;

  ui.Image? _srResult;
  bool _loading = false;
  bool _initialLoaded = false;
  Offset _focusNorm = const Offset(0.5, 0.5);

  @override
  void didUpdateWidget(SrPreviewOverlay old) {
    super.didUpdateWidget(old);
    if (old.sourceImage != widget.sourceImage) {
      _srResult?.dispose();
      _srResult = null;
      _initialLoaded = false;
      _loading = false;
    }
  }

  @override
  void dispose() {
    _srResult?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialLoaded && !_loading) {
      _initialLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runInference();
      });
    }

    // 根据显示区域缩放：手机 ~100px，桌面 ~200px
    final scale = (widget.displaySize.width / 600).clamp(0.4, 1.0);
    final size = _previewSize * scale;

    return GestureDetector(
      onTapDown: (d) {
        final size =
            _previewSize * (widget.displaySize.width / 600).clamp(0.4, 1.0);
        _focusNorm = Offset(
          (d.localPosition.dx / size).clamp(0.0, 1.0),
          (d.localPosition.dy / size).clamp(0.0, 1.0),
        );
        _runInference();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.elevatedBg,
          borderRadius: BorderRadius.circular(8 * scale),
          border: Border.all(color: AppColors.faintBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8 * scale,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _srResult != null
            ? RawImage(image: _srResult, fit: BoxFit.cover)
            : Center(
                child: _loading
                    ? SizedBox(
                        width: 24 * scale,
                        height: 24 * scale,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: AppColors.disabledText.withValues(alpha: 0.4),
                        size: 28 * scale,
                      ),
              ),
      ),
    );
  }

  Future<void> _runInference() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final image = widget.sourceImage;
      final srcW = image.width;
      final srcH = image.height;

      // 图片小于 cropSize 时用整张图
      final cropW = srcW < _cropSize ? srcW : _cropSize;
      final cropH = srcH < _cropSize ? srcH : _cropSize;

      final cx = (_focusNorm.dx * srcW).round().clamp(0, srcW - 1);
      final cy = (_focusNorm.dy * srcH).round().clamp(0, srcH - 1);
      final x0 = (cx - cropW ~/ 2).clamp(0, srcW - cropW);
      final y0 = (cy - cropH ~/ 2).clamp(0, srcH - cropH);

      // GPU 侧裁切
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(
          x0.toDouble(),
          y0.toDouble(),
          cropW.toDouble(),
          cropH.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(cropW, cropH);
      picture.dispose();

      final byteData = await cropped.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      cropped.dispose();
      if (byteData == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final result = await SrService.instance.upscaleRegion(
        rgbaBytes: byteData.buffer.asUint8List(),
        width: cropW,
        height: cropH,
      );

      if (mounted) {
        final old = _srResult;
        setState(() {
          _srResult = result;
          _loading = false;
        });
        old?.dispose();
      }
    } catch (e) {
      debugPrint('[SrPreview] Inference failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }
}
