import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../services/debug/debug_log_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Log message parsing
// ═══════════════════════════════════════════════════════════════════════════════

/// Parsed representation of a single log message.
class _ParsedLogEntry {
  final String? tag;
  final String message;
  final Color tagColor;
  final Color? semanticColor;
  final bool isError;

  const _ParsedLogEntry({
    required this.tag,
    required this.message,
    required this.tagColor,
    required this.semanticColor,
    required this.isError,
  });
}

/// Parses a raw log message (without timestamp) into structured parts.
///
/// Expected format: `[TagName] message` or plain `message` (no tag).
_ParsedLogEntry _parseLogMessage(String raw) {
  final match = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(raw);

  if (match != null) {
    final tag = match.group(1)!;
    final message = match.group(2)!;
    return _ParsedLogEntry(
      tag: tag,
      message: message,
      tagColor: _tagColor(tag),
      semanticColor: _semanticColor(message),
      isError: _isError(message),
    );
  }

  return _ParsedLogEntry(
    tag: null,
    message: raw,
    tagColor: AppColors.debugSystem,
    semanticColor: _semanticColor(raw),
    isError: _isError(raw),
  );
}

Color _tagColor(String tag) {
  final t = tag.toLowerCase();

  if (t == 'rawbridge' ||
      t == 'pipeline' ||
      t == 'previewrenderer' ||
      t == 'multipasspreview') {
    return AppColors.debugInfra;
  }
  if (t.startsWith('ai') ||
      t == 'sam' ||
      t == 'segmentation' ||
      t == 'smartregion' ||
      t == 'srpreview' ||
      t == 'srsection' ||
      t.startsWith('srservice')) {
    return AppColors.debugAi;
  }
  if (t.startsWith('imageloader') ||
      t.startsWith('imagenotifier') ||
      t.startsWith('imageutil') ||
      t == 'histogram') {
    return AppColors.debugImageIO;
  }
  if (t.startsWith('hdr') || t == 'luttexturecache') {
    return AppColors.debugProcessing;
  }
  if (t == 'exportqueue' ||
      t == 'sidecar' ||
      t == 'lutlibrary' ||
      t == 'presetnotifier' ||
      t == 'lutlibrarystate') {
    return AppColors.debugExportIO;
  }
  return AppColors.debugSystem;
}

Color? _semanticColor(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('failed') ||
      lower.contains('error') ||
      lower.contains('exception')) {
    return AppColors.semanticError;
  }
  if (lower.contains('skip') ||
      lower.contains('skipping') ||
      lower.contains('give up')) {
    return AppColors.semanticWarning;
  }
  if (lower.contains('done') ||
      lower.contains('complete') ||
      lower.contains('ready') ||
      lower.contains('initialized') ||
      lower.contains('imported') ||
      lower.contains('loaded')) {
    return AppColors.semanticSuccess;
  }
  return null;
}

bool _isError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('failed') ||
      lower.contains('error') ||
      lower.contains('exception');
}

// ═══════════════════════════════════════════════════════════════════════════════
// Log entry row widget
// ═══════════════════════════════════════════════════════════════════════════════

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontSize: 11,
  height: 1.4,
  letterSpacing: 0.3,
);

class _LogEntryRow extends StatelessWidget {
  final LogEntry entry;
  final _ParsedLogEntry? parsed; // pre-parsed, avoid re-parsing
  final bool isAlt;
  final bool isExpanded;
  final VoidCallback? onTap;

  const _LogEntryRow({
    required this.entry,
    this.parsed,
    this.isAlt = false,
    this.isExpanded = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = this.parsed ?? _parseLogMessage(entry.message);

    final t = entry.time;
    final ts =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';

    Color? rowBg;
    Border? rowBorder;
    if (parsed.isError) {
      rowBg = AppColors.debugErrorBg;
      rowBorder = const Border(
        left: BorderSide(color: AppColors.debugErrorBorder, width: 2),
      );
    } else if (isAlt) {
      rowBg = AppColors.debugRowAlt;
    }

    final msgColor = parsed.semanticColor ?? AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: rowBg, border: rowBorder),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ts, style: _mono.copyWith(color: AppColors.debugTimestamp)),
            const SizedBox(width: 8),
            if (parsed.tag != null) ...[
              _TagChip(label: parsed.tag!, color: parsed.tagColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                parsed.message,
                style: _mono.copyWith(color: msgColor),
                maxLines: isExpanded ? null : 1,
                overflow: isExpanded ? null : TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TagChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Debug Log Screen
// ═══════════════════════════════════════════════════════════════════════════════

enum _Filter { all, errors, ai, pipeline, export }

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final _service = DebugLogService.instance;
  final _expandedKeys = <String>{};
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  _Filter _filter = _Filter.all;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _service.logCount.addListener(_onNewLog);
    _syncTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _service.syncNewEntriesFromDisk(),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchCtrl.dispose();
    _service.logCount.removeListener(_onNewLog);
    super.dispose();
  }

  void _onNewLog() {
    if (mounted) setState(() {});
  }

  String _entryKey(LogEntry entry) =>
      '${entry.time.microsecondsSinceEpoch}_${entry.message.hashCode}';

  // ── Filter logic ──

  bool _matchesFilter(LogEntry entry, _ParsedLogEntry parsed) {
    if (_searchQuery.isNotEmpty) {
      if (!entry.message.toLowerCase().contains(_searchQuery)) return false;
    }
    return _matchesFilterCategory(parsed, _filter);
  }

  static bool _matchesFilterCategory(_ParsedLogEntry parsed, _Filter filter) {
    if (filter == _Filter.all) return true;
    final tag = parsed.tag?.toLowerCase() ?? '';

    switch (filter) {
      case _Filter.errors:
        return parsed.isError;
      case _Filter.ai:
        return tag.startsWith('ai') ||
            tag == 'sam' ||
            tag == 'segmentation' ||
            tag == 'smartregion' ||
            tag.startsWith('sr');
      case _Filter.pipeline:
        return tag == 'pipeline' ||
            tag == 'previewrenderer' ||
            tag == 'multipasspreview' ||
            tag.startsWith('hdr') ||
            tag == 'luttexturecache' ||
            tag == 'rawbridge';
      case _Filter.export:
        return tag == 'exportqueue' ||
            tag == 'sidecar' ||
            tag == 'lutlibrary' ||
            tag == 'presetnotifier';
      case _Filter.all:
        return true;
    }
  }

  static Map<_Filter, int> _computeFilterCounts(
    List<LogEntry> entries,
    Map<LogEntry, _ParsedLogEntry> parsedMap,
  ) {
    final counts = <_Filter, int>{for (final f in _Filter.values) f: 0};
    for (final entry in entries) {
      final parsed = parsedMap[entry]!;
      for (final f in _Filter.values) {
        if (f != _Filter.all && _matchesFilterCategory(parsed, f)) {
          counts[f] = counts[f]! + 1;
        }
      }
    }
    counts[_Filter.all] = entries.length;
    return counts;
  }

  // ── Floating card wrapper (matches DevelopScreen style) ──

  Widget _buildFloatingCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelBg,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final entries = _service.entries;

    // Pre-parse all entries once per frame
    final parsedMap = <LogEntry, _ParsedLogEntry>{
      for (final e in entries) e: _parseLogMessage(e.message),
    };

    final filtered = (_filter == _Filter.all && _searchQuery.isEmpty)
        ? entries
        : entries.where((e) => _matchesFilter(e, parsedMap[e]!)).toList();
    final filterCounts = _computeFilterCounts(entries, parsedMap);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(tr('debugLog')),
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: tr('debugClear'),
              onPressed: () {
                setState(() {
                  _service.clear();
                  _expandedKeys.clear();
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, size: 20),
            tooltip: tr('debugExport'),
            onPressed: entries.isEmpty ? null : _export,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (entries.isNotEmpty)
              _buildFloatingCard(child: _buildSearchBar()),
            if (entries.isNotEmpty) const SizedBox(height: 12),
            if (entries.isNotEmpty)
              _buildFloatingCard(child: _buildFilterBar(filterCounts)),
            if (entries.isNotEmpty) const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState()
                  : _buildFloatingCard(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final entry = filtered[filtered.length - 1 - i];
                          final key = _entryKey(entry);
                          final isExpanded = _expandedKeys.contains(key);

                          return _LogEntryRow(
                            entry: entry,
                            parsed: parsedMap[entry],
                            isAlt: i.isOdd,
                            isExpanded: isExpanded,
                            onTap: () {
                              setState(() {
                                isExpanded
                                    ? _expandedKeys.remove(key)
                                    : _expandedKeys.add(key);
                              });
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 48, color: AppColors.disabledText),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ? tr('debugNoMatch') : tr('debugLogEmpty'),
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.disabledText,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ──

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 30,
        child: TextField(
          controller: _searchCtrl,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: tr('debugSearchHint'),
            hintStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppColors.disabledText.withValues(alpha: 0.5),
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 14,
              color: AppColors.disabledText,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 30,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.disabledText,
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 30,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 0,
            ),
            filled: true,
            fillColor: AppColors.surfaceBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.lightBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.lightBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: AppColors.active.withValues(alpha: 0.4),
              ),
            ),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        ),
      ),
    );
  }

  // ── Filter bar ──

  Widget _buildFilterBar(Map<_Filter, int> counts) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildChip(
            _Filter.all,
            tr('debugFilterAll'),
            counts[_Filter.all] ?? 0,
          ),
          const SizedBox(width: 8),
          _buildChip(
            _Filter.errors,
            tr('debugFilterErrors'),
            counts[_Filter.errors] ?? 0,
          ),
          const SizedBox(width: 8),
          _buildChip(_Filter.ai, tr('debugFilterAI'), counts[_Filter.ai] ?? 0),
          const SizedBox(width: 8),
          _buildChip(
            _Filter.pipeline,
            tr('debugFilterPipeline'),
            counts[_Filter.pipeline] ?? 0,
          ),
          const SizedBox(width: 8),
          _buildChip(
            _Filter.export,
            tr('debugFilterExport'),
            counts[_Filter.export] ?? 0,
          ),
        ],
      ),
    );
  }

  Widget _buildChip(_Filter value, String label, int count) {
    final selected = _filter == value;
    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => setState(() {
          _filter = value;
          _expandedKeys.clear();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.activeBg : AppColors.subtleBorder,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.lightBorder : AppColors.dividerLine,
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.bodyLarge.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.disabledText,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: selected
                        ? AppColors.faintText
                        : AppColors.disabledText.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Export ──

  Future<void> _export() async {
    try {
      final tempFile = await _service.exportToFile();
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: tr('debugExport'),
      );
      if (dir == null) return;
      final dest = await tempFile.copy(p.join(dir, p.basename(tempFile.path)));
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
