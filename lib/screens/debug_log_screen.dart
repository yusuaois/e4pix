import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/debug/debug_log_service.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final _service = DebugLogService.instance;

  @override
  void initState() {
    super.initState();
    _service.logCount.addListener(_onNewLog);
  }

  @override
  void dispose() {
    _service.logCount.removeListener(_onNewLog);
    super.dispose();
  }

  void _onNewLog() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = _service.entries;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(tr('debugLog')),
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        actions: [
          if (entries.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _service.clear());
              },
              child: Text(tr('debugClear')),
            ),
          TextButton(
            onPressed: entries.isEmpty ? null : _export,
            child: Text(tr('debugExport')),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                tr('debugLogEmpty'),
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.disabledText,
                ),
              ),
            )
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final entry = entries[entries.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    entry.toLine(),
                    style: AppTypography.labelSmall.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.mediumText,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _export() async {
    try {
      final tempFile = await _service.exportToFile();
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: tr('debugExport'),
      );
      if (dir == null) return;
      final fileName = p.basename(tempFile.path);
      final dest = await tempFile.copy(p.join(dir, fileName));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('debugExported', args: [dest.path])),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('debugExportFailed', args: ['$e']))),
        );
      }
    }
  }
}
