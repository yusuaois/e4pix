import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../core/constants/app_info.dart';
import '../../services/app/update_service.dart';

class AboutTiles extends StatelessWidget {
  const AboutTiles({super.key});

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
            ListTile(
              leading: const Icon(Icons.info_outline, size: 20),
              title: Text(tr("version"), style: TextStyle(fontSize: 13.5)),
              trailing: Text(
                ver,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            ),
            const CheckUpdateTile(),
            ListTile(
              leading: const Icon(Icons.code, size: 20),
              title: Text(tr("projectUrl"), style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                AppInfo.repoDisplay,
                style: TextStyle(fontSize: 11, color: Colors.white54),
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

class CheckUpdateTile extends StatefulWidget {
  const CheckUpdateTile({super.key});
  @override
  State<CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends State<CheckUpdateTile> {
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
      leading: const Icon(Icons.system_update_alt, size: 20),
      title: Text(tr("checkUpdate"), style: const TextStyle(fontSize: 13.5)),
      trailing: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: _busy ? null : _check,
    );
  }
}

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
      backgroundColor: const Color(0xFF1A1A20),
      title: Text(
        tr("updateAvailable", args: [info.latestVersion]),
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: info.body.trim().isEmpty
              ? Text(
                  tr("updateNoNotes"),
                  style: const TextStyle(fontSize: 12.5, height: 1.5),
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
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 12.5, height: 1.5),
                    h2: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      height: 1.8,
                    ),
                    listBullet: const TextStyle(fontSize: 12.5),
                    blockquote: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white54,
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
        ),
      ),
      actions: [
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
      ],
    );
  }
}
