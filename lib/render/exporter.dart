import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:image/image.dart' as img_pkg;
import 'package:path/path.dart' as p;

import '../core/models/adjustment_params.dart';
import '../native/raw_bridge.dart';
import 'cpu_denoise.dart';
import 'export_template.dart';
import 'full_pipeline_renderer.dart';
import 'pixel_convert.dart';

enum ExportFormat { png, jpeg }

extension ExportFormatExt on ExportFormat {
  String get extension => switch (this) {
    ExportFormat.png => 'png',
    ExportFormat.jpeg => 'jpg',
  };
}

typedef ExportProgress = void Function(double fraction, String stage);

/// 全分辨率导出
///
/// 解码 RAW →（可选）降噪 → 转 8-bit sRGB → 渲染完整管线 → 编码 → 写文件
///
/// 文件名由 [ExportTemplate] 模板生成：解码后 metadata 可用，填充占位符
/// （日期/相机/ISO 等），经非法字符清理与批量去重（[usedNames]）后得到最终路径。
///
/// 降噪两路互斥：
/// - [DenoiseEngine.cpu]：16-bit 线性域 CPU 并行降噪，渲染时不传 denoiseProgram。
/// - [DenoiseEngine.gpu]：普通转换，渲染时传 denoiseProgram，由 GPU pass 降噪。
class Exporter {
  Exporter._();

  /// 导出单张，返回写出的文件。
  ///
  /// [outputDir] 输出目录；[filenameTemplate] 文件名模板（见 [ExportTemplate]）；
  /// [seq] 1-based 序号（批量用）；[usedNames] 跨多次调用累积的已用文件名集合，
  /// 用于批量去重（单张可传新的空集）。
  static Future<File> exportFullRes({
    required String inputRawPath,
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
    ui.Image? curveTexture,
    ui.FragmentProgram? sharpenProgram,
    ui.FragmentProgram? denoiseProgram,
    DenoiseEngine denoiseEngine = DenoiseEngine.cpu,
    int denoiseParallelism = 4,
    int jpegQuality = 95,
    ExportProgress? onProgress,
  }) async {
    onProgress?.call(0.05, tr('exportDecodingImage'));
    final raw = await RawBridge.decodeFull(inputRawPath);

    final sourceImage = await _prepareSourceImage(
      raw: raw,
      params: params,
      denoiseEngine: denoiseEngine,
      denoiseParallelism: denoiseParallelism,
      onProgress: onProgress,
    );

    onProgress?.call(0.80, tr('exportRenderingImage'));
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
      denoiseProgram: _wantGpuDenoise(params, denoiseEngine)
          ? denoiseProgram
          : null,
      targetWidth: sourceImage.width,
      targetHeight: sourceImage.height,
    );

    // 文件名：模板 + metadata + 去重
    final base = ExportTemplate.apply(
      template: filenameTemplate,
      originalName: ExportTemplate.stripExtension(p.basename(inputRawPath)),
      seq: seq,
      metadata: raw.metadata,
      outWidth: output.width,
      outHeight: output.height,
    );
    final filename = ExportTemplate.ensureUnique(
      base: base,
      extension: format.extension,
      used: usedNames,
    );
    final outputPath = p.join(outputDir, filename);

    final bytes = await _encode(output, format, jpegQuality);
    output.dispose();

    onProgress?.call(0.95, tr('writingFile'));
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    onProgress?.call(1.0, tr('completed'));
    return file;
  }

  /// 解码后 → 渲染前：准备 develop 用的 8-bit sRGB 源图（按需 CPU 降噪）。
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

  /// 渲染输出 → 编码字节（PNG 直接编码，JPEG 在 isolate 用 image 包）
  static Future<Uint8List> _encode(
    ui.Image output,
    ExportFormat format,
    int jpegQuality,
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
