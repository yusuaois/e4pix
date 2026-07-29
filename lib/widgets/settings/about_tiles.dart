import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/app/update_service.dart';
import '../../services/lens/lensfun_update_service.dart';

class AboutTiles extends StatelessWidget {
  final BorderRadius? tileBorderRadius;
  const AboutTiles({super.key, this.tileBorderRadius});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (ctx, snap) {
        final ver = snap.hasData
            ? '${snap.data!.version} (${snap.data!.buildNumber})'
            : '...';
        return Column(
          children: [
            _VersionTile(version: ver),
            const LensfunDatabaseTile(),
            ListTile(
              shape: tileBorderRadius != null
                  ? RoundedRectangleBorder(borderRadius: tileBorderRadius!)
                  : null,
              leading: const Icon(Icons.code, size: 20),
              title: Text(tr("projectUrl"), style: AppTypography.titleMedium),
              subtitle: Text(
                AppInfo.repoDisplay,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.faintText,
                ),
              ),
              trailing: const Icon(Icons.open_in_new, size: 14),
              onTap: () {
                url_launcher.launchUrl(Uri.parse(AppInfo.repoUrl));
              },
            ),
          ],
        );
      },
    );
  }
}

// ── Version 行（单击检查更新 / 长按变更日志）────────────────────────

class _VersionTile extends StatefulWidget {
  final String version;
  const _VersionTile({required this.version});

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    UpdateInfo? info;
    try {
      info = await UpdateService.check();
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (info == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr("updateCheckFailed"))));
      return;
    }
    if (!info.hasUpdate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr("updateUpToDate"))));
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => UpdateDialog(info: info!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline, size: 20),
      title: Text(tr("version"), style: AppTypography.titleMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.version,
            style: AppTypography.bodySmall.copyWith(
              fontFamily: 'monospace',
              color: AppColors.mediumText,
            ),
          ),
          const SizedBox(width: 4),
          _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward_ios, size: 14),
        ],
      ),
      onTap: _busy ? null : _check,
      onLongPress: () {
        showDialog(
          context: context,
          builder: (_) => ChangelogDialog(version: widget.version),
        );
      },
    );
  }
}

// ── LensFun 数据库行 ───────────────────────────────────────────────

class LensfunDatabaseTile extends StatefulWidget {
  const LensfunDatabaseTile({super.key});

  @override
  State<LensfunDatabaseTile> createState() => _LensfunDatabaseTileState();
}

class _LensfunDatabaseTileState extends State<LensfunDatabaseTile> {
  bool _busy = false;
  String? _sha;

  @override
  void initState() {
    super.initState();
    _loadSha();
  }

  Future<void> _loadSha() async {
    final sha = await LensfunUpdateService.localSha();
    if (mounted) setState(() => _sha = sha);
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final latest = await LensfunUpdateService.fetchLatestSha();
      if (latest == null) {
        debugPrint('[LensfunDB] Manual check: fetchLatestSha returned null');
        _showSnack(tr("updateCheckFailed"));
        return;
      }
      debugPrint(
        '[LensfunDB] Manual check: latest SHA=$latest, local SHA=${_sha ?? "none"}',
      );
      if (latest == _sha) {
        debugPrint('[LensfunDB] Manual check: already up to date');
        _showSnack(tr("lensfunUpToDate"));
        return;
      }
      debugPrint('[LensfunDB] Manual check: downloading $latest');
      final ok = await LensfunUpdateService.downloadAndExtract(latest);
      if (ok) {
        setState(() => _sha = latest);
        debugPrint('[LensfunDB] Manual check: updated to $latest');
        _showSnack(tr("lensfunUpdated"));
      } else {
        debugPrint('[LensfunDB] Manual check: downloadAndExtract failed');
        _showSnack(tr("updateCheckFailed"));
      }
    } catch (e) {
      debugPrint('[LensfunDB] Manual check error: $e');
      _showSnack(tr("updateCheckFailed"));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final shortSha = _sha != null && _sha!.length >= 7
        ? _sha!.substring(0, 7)
        : (_sha ?? '--');
    return ListTile(
      leading: const Icon(Icons.camera_alt_outlined, size: 20),
      title: Text(tr("lensfunDatabase"), style: AppTypography.titleMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shortSha,
            style: AppTypography.bodySmall.copyWith(
              fontFamily: 'monospace',
              color: AppColors.mediumText,
            ),
          ),
          const SizedBox(width: 4),
          _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward_ios, size: 14),
        ],
      ),
      onTap: _busy ? null : _check,
    );
  }
}

// ── UpdateDialog ───────────────────────────────────────────────────

class UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  final bool showIgnore;
  const UpdateDialog({super.key, required this.info, this.showIgnore = false});

  Future<void> _download(BuildContext context) async {
    final asset = await info.assetForPlatform();
    if (asset == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr("updateNoAsset"))));
      }
      url_launcher.launchUrl(
        Uri.parse(info.releaseUrl),
        mode: url_launcher.LaunchMode.externalApplication,
      );
      return;
    }
    url_launcher.launchUrl(
      Uri.parse(asset.url),
      mode: url_launcher.LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.elevatedBg,
      title: Text(
        tr("updateAvailable", args: [info.latestVersion]),
        style: AppTypography.headlineMedium,
      ),
      content: _buildContent(),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent() {
    return SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: info.body.trim().isEmpty
            ? Text(
                tr("updateNoNotes"),
                style: AppTypography.titleSmall.copyWith(height: 1.5),
              )
            : MarkdownBody(
                data: info.body,
                onTapLink: (text, href, title) {
                  if (href != null) {
                    url_launcher.launchUrl(
                      Uri.parse(href),
                      mode: url_launcher.LaunchMode.externalApplication,
                    );
                  }
                },
                styleSheet: _buildMarkdownStyleSheet(),
              ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet() {
    return MarkdownStyleSheet(
      p: AppTypography.titleSmall.copyWith(height: 1.5),
      h2: AppTypography.headlineSmall.copyWith(
        fontWeight: FontWeight.bold,
        height: 1.8,
      ),
      listBullet: AppTypography.titleSmall,
      code: AppTypography.bodySmall.copyWith(
        fontFamily: 'monospace',
        color: AppColors.semanticWarning,
        backgroundColor: AppColors.faintBorder,
        letterSpacing: 1.0,
      ),
      blockquote: AppTypography.bodyMedium.copyWith(
        color: AppColors.faintText,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.faintBorder,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      if (showIgnore)
        TextButton(
          onPressed: () {
            UpdateService.ignoreVersion(info.latestVersion);
            Navigator.pop(context);
          },
          child: Text(tr("updateIgnore")),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr("updateLater")),
      ),
      TextButton(
        onPressed: () {
          url_launcher.launchUrl(
            Uri.parse(info.releaseUrl),
            mode: url_launcher.LaunchMode.externalApplication,
          );
        },
        child: Text(tr("updateOpenPage")),
      ),
      FilledButton(
        onPressed: () => _download(context),
        child: Text(tr("updateDownload")),
      ),
    ];
  }
}

// ── ChangelogDialog ────────────────────────────────────────────────

class ChangelogDialog extends StatelessWidget {
  final String version;
  const ChangelogDialog({super.key, required this.version});

  static final _mdStyleSheet = MarkdownStyleSheet(
    p: AppTypography.titleSmall.copyWith(height: 1.5),
    h2: AppTypography.headlineSmall.copyWith(
      fontWeight: FontWeight.bold,
      height: 1.8,
    ),
    listBullet: AppTypography.titleSmall,
    code: AppTypography.bodySmall.copyWith(
      fontFamily: 'monospace',
      color: AppColors.semanticWarning,
      backgroundColor: AppColors.faintBorder,
      letterSpacing: 1.0,
    ),
    blockquote: AppTypography.bodyMedium.copyWith(color: AppColors.faintText),
    blockquoteDecoration: BoxDecoration(
      color: AppColors.faintBorder,
      borderRadius: BorderRadius.circular(4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.elevatedBg,
      title: Text(
        tr('changelogTitle', args: [version]),
        style: AppTypography.headlineMedium,
      ),
      content: _buildChangelogContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('close')),
        ),
      ],
    );
  }

  Widget _buildChangelogContent() {
    return SizedBox(
      width: 360,
      child: FutureBuilder<String>(
        future: rootBundle.loadString('assets/changelog/CHANGELOG.md'),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final raw = snap.data!.trim();
          // Strip empty section headers (## heading with no content before next ## or ---)
          final stripped = raw.replaceAll(
            RegExp(r'^##[^\n]*\s+(?=##|\Z)', multiLine: true, dotAll: true),
            '',
          );
          // Strip download notes / SHA section after ---
          final cutIdx = stripped.indexOf('\n---');
          final body =
              (cutIdx >= 0 ? stripped.substring(0, cutIdx) : stripped).trim();
          if (body.isEmpty) {
            return Text(
              tr('changelogUnavailable'),
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.faintText,
              ),
            );
          }
          return SingleChildScrollView(
            child: MarkdownBody(data: body, styleSheet: _mdStyleSheet),
          );
        },
      ),
    );
  }
}
