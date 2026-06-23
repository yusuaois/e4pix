import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:image/image.dart' as img_pkg;
import 'package:path/path.dart' as p;

import '../services/sr/sr_service.dart';

import '../core/constants/raw_formats.dart';
import '../core/models/adjustment_params.dart';
import '../core/models/watermark_config.dart';
import '../native/raw_bridge.dart';
import '../services/image/image_loader.dart';
import 'cpu_denoise.dart';
import 'curve_baker.dart';
import 'exif_writer.dart';
import 'export_template.dart';
import 'full_pipeline_renderer.dart';
import 'pixel_convert.dart';
import 'watermark_exporter.dart';

enum ExportFormat { png, jpeg }

extension ExportFormatExt on ExportFormat {
  String get extension => switch (this) {
    ExportFormat.png => 'png',
    ExportFormat.jpeg => 'jpg',
  };
}

typedef ExportProgress = void Function(double fraction, String stage);

/// 取消检查回调：返回 true 表示该任务已被取消，应中止
typedef CancelCheck = bool Function();

/// 导出被取消时抛出
class ExportCancelledException implements Exception {
  const ExportCancelledException();
  @override
  String toString() => 'ExportCancelledException';
}

/// 全分辨率导出
///
/// 解码 RAW →（可选）降噪 → 转 8-bit sRGB → 渲染完整管线 → 编码 → 写文件
///
/// curve：每张图按自身 [AdjustmentParams.curves] 现生成纹理
/// LUT：由调用方传入纹理引用
///
/// 中断：[isCancelled] 在各阶段之间检查；命中则抛 [ExportCancelledException]
/// 中断粒度为阶段间（解码后 / 渲染后 / 编码后），最坏等当前阶段结束
class Exporter {
  Exporter._();

  static void _checkCancel(CancelCheck? isCancelled) {
    if (isCancelled?.call() ?? false) throw const ExportCancelledException();
  }

  static Future<File> exportFullRes({
    required String inputPath,
    required String outputDir,
    required String filenameTemplate,
    required int seq,
    required Set<String> usedNames,
    required ExportFormat format,
    required ui.FragmentProgram shaderProgram,
    required ui.FragmentProgram maskProgram,
    required AdjustmentParams params,
    ui.Image? lutTexture,
    int lutSize = 0,
    ui.Image? lutTextureB,
    int lutSizeB = 0,
    ui.FragmentProgram? sharpenProgram,
    ui.FragmentProgram? denoiseProgram,
    DenoiseEngine denoiseEngine = DenoiseEngine.cpu,
    int denoiseParallelism = 4,
    int jpegQuality = 95,
    bool writeExif = true,
    ExportProgress? onProgress,
    CancelCheck? isCancelled,
    WatermarkConfig? watermarkConfig,
  }) async {
    _checkCancel(isCancelled);
    onProgress?.call(0.05, tr('exportDecodingImage'));

    final ui.Image sourceImage;
    final RawMetadata metadata;
    final bool isStandard = RawFormats.isStandard(inputPath);

    if (isStandard) {
      // 标准图片：8-bit sRGB 无 16-bit、无 CPU 降噪
      final (image, meta) = await ImageLoader.decodeFull(inputPath);
      sourceImage = image;
      metadata = meta;
    } else {
      // RAW：解码 16-bit linear → (可选 CPU 降噪) → 8-bit sRGB
      final raw = await RawBridge.decodeFull(inputPath);
      metadata = raw.metadata;
      sourceImage = await _prepareSourceImage(
        raw: raw,
        params: params,
        denoiseEngine: denoiseEngine,
        denoiseParallelism: denoiseParallelism,
        onProgress: onProgress,
      );
    }

    _checkCancel(isCancelled); // 解码后检查点

    // curve 纹理
    ui.Image? curveTexture;
    try {
      curveTexture = await bakeCurveTexture(params.curves);

      onProgress?.call(0.80, tr('exportRenderingImage'));
      final passDenoiseProgram = isStandard
          ? (_wantDenoise(params) ? denoiseProgram : null)
          : (_wantGpuDenoise(params, denoiseEngine) ? denoiseProgram : null);

      final output = await FullPipelineRenderer.render(
        developProgram: shaderProgram,
        maskProgram: maskProgram,
        sourceImage: sourceImage,
        params: params,
        lutTexture: lutTexture,
        lutSize: lutSize,
        lutTextureB: lutTextureB,
        lutSizeB: lutSizeB,
        curveTexture: curveTexture,
        sharpenProgram: sharpenProgram,
        denoiseProgram: passDenoiseProgram,
        targetWidth: sourceImage.width,
        targetHeight: sourceImage.height,
      );

      // 源图与 curve 纹理渲染后即可释放
      sourceImage.dispose();
      curveTexture?.dispose();
      curveTexture = null;

      _checkCancel(isCancelled); // 渲染后检查点

      // 超分辨率后处理
      ui.Image finalOutput = output;
      if (params.srEnabled) {
        _checkCancel(isCancelled);
        onProgress?.call(0.83, tr('exportSuperRes'));
        ui.Image? srResult;
        bool srDone = false;
        SrService.instance
            .upscaleFull(
              source: output,
              onProgress: (p) {
                onProgress?.call(0.83 + p * 0.07, tr('exportSuperRes'));
              },
            )
            .then((r) {
              srResult = r;
              srDone = true;
            })
            .catchError((e) {
              dev.log('Super resolution failed: $e');
              srDone = true;
            });
        while (!srDone) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (isCancelled?.call() ?? false) {
            dev.log('SR cancelled, killing isolate');
            SrService.instance.cancelExport();
            throw const ExportCancelledException();
          }
        }
        if (srResult != null) {
          output.dispose();
          finalOutput = srResult!;
        }
      }

      // 水印边框合成
      if (watermarkConfig != null && watermarkConfig.enabled) {
        onProgress?.call(0.85, tr("exportWatermarkBorder"));
        try {
          final composited = await WatermarkExporter.composite(
            fullResImage: finalOutput,
            config: watermarkConfig,
            metadata: metadata,
          );
          if (finalOutput != output) finalOutput.dispose();
          finalOutput = composited;
        } catch (e) {
          dev.log(
            'Watermark composite failed, exporting without watermark: $e',
          );
        }
      }

      try {
        // 文件名：模板 + metadata + 去重
        final base = ExportTemplate.apply(
          template: filenameTemplate,
          originalName: ExportTemplate.stripExtension(p.basename(inputPath)),
          seq: seq,
          metadata: metadata,
          outWidth: finalOutput.width,
          outHeight: finalOutput.height,
        );
        final filename = ExportTemplate.ensureUnique(
          base: base,
          extension: format.extension,
          used: usedNames,
        );
        final outputPath = p.join(outputDir, filename);

        final writeMeta =
            !(watermarkConfig?.enabled ?? false) &&
            writeExif &&
            _hasValidMetadata(metadata);
        final bytes = await _encode(
          finalOutput,
          format,
          jpegQuality,
          writeMeta ? metadata : null,
        );

        _checkCancel(isCancelled); // 编码后检查点（写文件前）

        onProgress?.call(0.95, tr('writingFile'));
        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        onProgress?.call(1.0, tr('completed'));
        return file;
      } finally {
        finalOutput.dispose();
      }
    } catch (_) {
      curveTexture?.dispose();
      rethrow;
    }
  }

  static bool _hasValidMetadata(RawMetadata m) =>
      m.cameraModel.trim().isNotEmpty ||
      m.cameraMake.trim().isNotEmpty ||
      m.iso > 0 ||
      m.timestamp != null;

  static Future<ui.Image> _prepareSourceImage({
    required RawDecodedImage raw,
    required AdjustmentParams params,
    required DenoiseEngine denoiseEngine,
    required int denoiseParallelism,
    ExportProgress? onProgress,
  }) {
    if (_wantCpuDenoise(params, denoiseEngine)) {
      return PixelConvert.rawToImageWithDenoise(
        raw,
        params.denoiseLuma / 100.0,
        params.denoiseColor / 100.0,
        onProgress: onProgress,
        denoiseStage: tr('exportDenoising'),
        convertStage: tr('exportTransformingColorSpace'),
        progressStart: 0.10,
        progressEnd: 0.78,
        parallelism: denoiseParallelism,
      );
    }
    onProgress?.call(0.40, tr('exportTransformingColorSpace'));
    return PixelConvert.rawToImage(raw);
  }

  static Future<Uint8List> _encode(
    ui.Image output,
    ExportFormat format,
    int jpegQuality,
    RawMetadata? exifMetadata,
  ) async {
    switch (format) {
      case ExportFormat.png:
        final bd = await output.toByteData(format: ui.ImageByteFormat.png);
        return bd!.buffer.asUint8List();
      case ExportFormat.jpeg:
        final bd = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
        final w = output.width, h = output.height;
        final buffer = bd!.buffer;
        return Isolate.run(() {
          final image = img_pkg.Image.fromBytes(
            width: w,
            height: h,
            bytes: buffer,
            order: img_pkg.ChannelOrder.rgba,
          );
          if (exifMetadata != null) {
            writeExifToImage(image, exifMetadata);
          }
          return img_pkg.encodeJpg(image, quality: jpegQuality);
        });
    }
  }

  static bool _wantDenoise(AdjustmentParams p) =>
      p.denoiseLuma > 0.001 || p.denoiseColor > 0.001;

  static bool _wantCpuDenoise(AdjustmentParams p, DenoiseEngine e) =>
      _wantDenoise(p) && e == DenoiseEngine.cpu;

  static bool _wantGpuDenoise(AdjustmentParams p, DenoiseEngine e) =>
      _wantDenoise(p) && e == DenoiseEngine.gpu;
}
