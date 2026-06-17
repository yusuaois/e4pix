import 'package:e4pix/state/export/export_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_colors.dart';

import '../../core/theme/app_typography.dart';
import '../../render/cpu_denoise.dart';
import '../../render/export_template.dart';
import '../../render/exporter.dart';

/// 导出对话框的返回结果
class ExportDialogResult {
  final ExportFormat format;
  final int jpegQuality;
  final String filenameTemplate;
  final bool writeExif;
  final DenoiseEngine denoiseEngine;

  const ExportDialogResult({
    required this.format,
    required this.jpegQuality,
    required this.filenameTemplate,
    required this.writeExif,
    required this.denoiseEngine,
  });
}

/// 弹出导出配置对话框，返回 null 表示取消
/// [tasks] 用于判断批量、取首图名做预览、检测是否有降噪
Future<ExportDialogResult?> showExportDialog(
  BuildContext context, {
  required List<ExportTask> tasks,
  required int initialQuality,
  required String initialTemplate,
}) {
  ExportFormat format = ExportFormat.png;
  int quality = initialQuality;
  DenoiseEngine denoiseEngine = DenoiseEngine.cpu;
  String template = initialTemplate;
  bool writeExif = true;

  final hasDenoise = tasks.any(
    (t) => t.params.denoiseLuma > 0.001 || t.params.denoiseColor > 0.001,
  );
  final isBatch = tasks.length > 1;
  final firstName = ExportTemplate.stripExtension(p.basename(tasks.first.path));

  return showDialog<ExportDialogResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(
          isBatch
              ? '${tr('exportBatch')}  ·  ${tasks.length}'
              : tr('exportImage'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('format'), style: AppTypography.bodyLarge),
              const SizedBox(height: 8),
              SegmentedButton<ExportFormat>(
                segments: const [
                  ButtonSegment(value: ExportFormat.png, label: Text('PNG')),
                  ButtonSegment(value: ExportFormat.jpeg, label: Text('JPEG')),
                ],
                selected: {format},
                onSelectionChanged: (s) => setS(() => format = s.first),
              ),
              if (format == ExportFormat.jpeg) ...[
                const SizedBox(height: 14),
                Text(
                  '${tr('quality')}: $quality',
                  style: AppTypography.bodyLarge,
                ),
                Slider(
                  value: quality.toDouble(),
                  min: 50,
                  max: 100,
                  onChanged: (v) => setS(() => quality = v.round()),
                ),
              ],
              const SizedBox(height: 14),
              Text(tr('exportFilename'), style: AppTypography.bodyLarge),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: template,
                style: AppTypography.bodyLarge.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: ExportTemplate.defaultTemplate,
                  suffixText: '.${format.extension}',
                ),
                onChanged: (v) => setS(() => template = v),
              ),
              const SizedBox(height: 4),
              Text(
                '${tr('exportFilenamePreview')}: '
                '${ExportTemplate.apply(template: template.isEmpty ? ExportTemplate.defaultTemplate : template, originalName: firstName, seq: 1)}.${format.extension}',
                style: AppTypography.labelMedium.copyWith(
                  fontFamily: 'monospace',
                  color: AppColors.semanticSuccess.withValues(alpha: 0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (isBatch &&
                  !ExportTemplate.hasDistinctToken(
                    template.isEmpty
                        ? ExportTemplate.defaultTemplate
                        : template,
                  )) ...[
                const SizedBox(height: 4),
                Text(
                  tr('exportFilenameBatchWarn'),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.semanticWarning.withValues(alpha: 0.8),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '{name} {seq} {seq3} {date} {camera} {iso}',
                  style: AppTypography.labelSmall.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.disabledText,
                  ),
                ),
              ),
              if (hasDenoise) ...[
                const SizedBox(height: 14),
                Text(tr('denoiseEngine'), style: AppTypography.bodyLarge),
                const SizedBox(height: 8),
                SegmentedButton<DenoiseEngine>(
                  segments: [
                    ButtonSegment(
                      value: DenoiseEngine.cpu,
                      label: Text(
                        tr('denoiseEngineCpu'),
                        style: AppTypography.bodySmall,
                      ),
                    ),
                    ButtonSegment(
                      value: DenoiseEngine.gpu,
                      label: Text(
                        tr('denoiseEngineGpu'),
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                  selected: {denoiseEngine},
                  onSelectionChanged: (s) =>
                      setS(() => denoiseEngine = s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  denoiseEngine == DenoiseEngine.cpu
                      ? tr('denoiseEngineCpuHint')
                      : tr('denoiseEngineGpuHint'),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.faintText,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                tr('exportDescription'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.mediumText,
                ),
              ),
              if (format == ExportFormat.jpeg) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: writeExif,
                  title: Text(
                    tr('exportWriteExif'),
                    style: AppTypography.titleSmall,
                  ),
                  subtitle: Text(
                    tr('exportWriteExifDesc'),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.faintText,
                    ),
                  ),
                  onChanged: (v) => setS(() => writeExif = v ?? true),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              ExportDialogResult(
                format: format,
                jpegQuality: quality,
                filenameTemplate: template.isEmpty
                    ? ExportTemplate.defaultTemplate
                    : template,
                writeExif: writeExif,
                denoiseEngine: denoiseEngine,
              ),
            ),
            child: Text(tr('export')),
          ),
        ],
      ),
    ),
  );
}
