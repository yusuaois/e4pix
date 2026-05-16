import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/models/adjustment_params.dart';
import '../services/ai/ai_color_service.dart';

class AISuggestionDialog extends StatefulWidget {
  final AdjustmentParams currentParams;
  final Future<String> Function() renderPreviewToFile;
  final AIColorSuggestion? initialSuggestion;

  const AISuggestionDialog({
    super.key,
    required this.currentParams,
    required this.renderPreviewToFile,
    this.initialSuggestion,
  });

  @override
  State<AISuggestionDialog> createState() => _AISuggestionDialogState();
}

class _AISuggestionDialogState extends State<AISuggestionDialog> {
  final _intentController = TextEditingController();
  bool _loading = false;
  AIColorSuggestion? _suggestion;
  String? _error;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    if (widget.initialSuggestion != null) {
      _suggestion = widget.initialSuggestion;
    }
  }

  @override
  void dispose() {
    _intentController.dispose();
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    final p = _tempPath;
    _tempPath = null;
    if (p != null) {
      File(p).delete().catchError((_) => File(p));
    }
  }

  Future<void> _runSuggestion() async {
    setState(() {
      _loading = true;
      _error = null;
      _suggestion = null;
    });

    try {
      _tempPath = await widget.renderPreviewToFile();
      final bytes = await File(_tempPath!).readAsBytes();

      final result = await AIColorService.suggest(
        imageBytes: bytes,
        currentParams: widget.currentParams,
        userIntent: _intentController.text,
      );

      if (mounted) setState(() => _suggestion = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _cleanup();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: Color(0xFF6B5BFF)),
          SizedBox(width: 8),
          Text(tr("aiColorSuggestion")),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _intentController,
              enabled: !_loading,
              decoration: InputDecoration(
                hintText: tr("aiColorSuggestionPrompt"),
                hintStyle: const TextStyle(fontSize: 11.5),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(height: 10),
                      Text(
                        tr("aiColorInProgress"),
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              )
            else if (_suggestion != null)
              _SuggestionView(suggestion: _suggestion!)
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  tr("aiColorSuggestionDescription"),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(tr("cancel")),
        ),
        if (_suggestion == null)
          FilledButton.icon(
            onPressed: _loading ? null : _runSuggestion,
            icon: const Icon(Icons.auto_awesome, size: 14),
            label: Text(tr("aiColorSuggestionRequest")),
          )
        else ...[
          TextButton(
            onPressed: () => setState(() {
              _suggestion = null;
              _error = null;
            }),
            child: Text(tr("aiColorSuggestionRegenerate")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _suggestion),
            child: Text(tr("aiColorSuggestionApply")),
          ),
        ],
      ],
    );
  }
}

class _SuggestionView extends StatelessWidget {
  final AIColorSuggestion suggestion;
  const _SuggestionView({required this.suggestion});

  String _fmt(String key, num v) {
    switch (key) {
      case 'exposure':
        return '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)} EV';
      case 'temperature':
        return '${v.toInt()} K';
      default:
        return v > 0 ? '+${v.toInt()}' : v.toInt().toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final basic = suggestion.raw.entries.where((e) => e.value != null).toList();
    final hslRaw = suggestion.hslRaw;

    final hslRows = <Widget>[];
    if (hslRaw != null) {
      for (final band in _hslBandNames) {
        final m = hslRaw[band];
        if (m is! Map) continue;
        final parts = <String>[];
        for (final field in ['h', 's', 'l']) {
          final v = m[field];
          if (v is num) {
            parts.add('${field.toUpperCase()} ${v > 0 ? '+' : ''}${v.toInt()}');
          }
        }
        if (parts.isEmpty) continue;
        hslRows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: [
                Expanded(
                  child: Text(band, style: const TextStyle(fontSize: 11)),
                ),
                Text(
                  parts.join('  '),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: Colors.greenAccent.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (suggestion.mood.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF6B5BFF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              suggestion.mood,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B5BFF),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (suggestion.reasoning.isNotEmpty)
          Text(
            suggestion.reasoning,
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        const SizedBox(height: 12),

        // —— 基础滑块 ——
        if (basic.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E14),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              children: basic
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          Text(
                            _fmt(e.key, e.value!),
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.greenAccent.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

        // —— HSL ——
        if (hslRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E14),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HSL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...hslRows,
              ],
            ),
          ),
        ],

        if (basic.isEmpty && hslRows.isEmpty)
          Text(
            tr("aiColorSuggestionNone"),
            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic),
          ),
      ],
    );
  }
}

const _hslBandNames = [
  'red',
  'orange',
  'yellow',
  'green',
  'aqua',
  'blue',
  'purple',
  'magenta',
];
