import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../screens/debug_log_screen.dart';
import '../../services/debug/debug_log_service.dart';

class DebugModeTile extends StatefulWidget {
  final BorderRadius? tileBorderRadius;
  const DebugModeTile({super.key, this.tileBorderRadius});

  @override
  State<DebugModeTile> createState() => _DebugModeTileState();
}

class _DebugModeTileState extends State<DebugModeTile> {
  final _service = DebugLogService.instance;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          shape: !_service.enabled && widget.tileBorderRadius != null
              ? RoundedRectangleBorder(borderRadius: widget.tileBorderRadius!)
              : null,
          secondary: const Icon(Icons.bug_report_outlined, size: 20),
          title: Text(tr('debugMode'), style: AppTypography.titleMedium),
          subtitle: Text(
            tr('debugModeHint'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.faintText),
          ),
          value: _service.enabled,
          onChanged: (v) => setState(() => _service.enabled = v),
        ),
        if (_service.enabled)
          ListTile(
            shape: widget.tileBorderRadius != null
                ? RoundedRectangleBorder(borderRadius: widget.tileBorderRadius!)
                : null,
            leading: const Icon(Icons.article_outlined, size: 20),
            title: Text(tr('debugViewLogs'), style: AppTypography.titleMedium),
            subtitle: Text(
              tr('debugLogCount', args: ['${_service.length}']),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.faintText,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugLogScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }
}
