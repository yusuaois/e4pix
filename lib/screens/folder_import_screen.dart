import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/constants/raw_formats.dart';
import '../native/raw_bridge.dart';
import '../services/permission/storage_permission_service.dart';

Future<List<String>?> openFolderImport(NavigatorState navigator) async {
  // Android：RAW 按文件路径读取需要「所有文件访问」权限
  if (Platform.isAndroid &&
      !await StoragePermissionService.requestAllFilesAccess()) {
    return null;
  }
  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: tr('folderImportPickDir'),
  );
  if (dir == null || dir.isEmpty || dir == '/') return null;

  return navigator.push<List<String>>(
    MaterialPageRoute(builder: (_) => _FolderImportScreen(dirPath: dir)),
  );
}

class _FolderImportScreen extends StatefulWidget {
  final String dirPath;
  const _FolderImportScreen({required this.dirPath});

  @override
  State<_FolderImportScreen> createState() => _FolderImportScreenState();
}

class _FolderImportScreenState extends State<_FolderImportScreen> {
  List<String> _rawPaths = [];
  final Set<String> _selected = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    try {
      final dir = Directory(widget.dirPath);
      if (!await dir.exists()) {
        setState(() {
          _error = tr('folderImportNotFound');
          _loading = false;
        });
        return;
      }
      final paths = <String>[];
      await for (final e in dir.list(recursive: false, followLinks: false)) {
        if (e is File && RawFormats.isSupported(e.path)) {
          paths.add(e.path);
        }
      }
      paths.sort(
        (a, b) =>
            p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _rawPaths = paths;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 手动下拉刷新：重新扫描目录
  Future<void> _refresh() => _scan();

  void _toggle(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  void _selectAll() => setState(() => _selected.addAll(_rawPaths));
  void _selectNone() => setState(() => _selected.clear());

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _rawPaths.isNotEmpty && _selected.length == _rawPaths.length;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: _buildAppBar(allSelected),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar(bool allSelected) {
    return AppBar(
      backgroundColor: AppColors.scaffoldBg,
      title: Text(
        p.basename(widget.dirPath),
        style: AppTypography.headlineSmall,
      ),
      actions: [
        if (_rawPaths.isNotEmpty)
          TextButton(
            onPressed: allSelected ? _selectNone : _selectAll,
            child: Text(
              allSelected ? tr('deselectAll') : tr('selectAll'),
              style: AppTypography.bodyLarge,
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _error != null
          ? _buildScrollableMessage(
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.semanticWarning),
              ),
            )
          : _rawPaths.isEmpty
          ? _buildScrollableMessage(
              Text(
                tr('folderImportEmpty'),
                style: TextStyle(color: AppColors.faintText),
              ),
            )
          : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 1.1,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _rawPaths.length,
      itemBuilder: (ctx, i) {
        final path = _rawPaths[i];
        return _RawGridTile(
          key: ValueKey(path),
          path: path,
          selected: _selected.contains(path),
          onTap: () => _toggle(path),
        );
      },
    );
  }

  /// 让空/错误态也能下拉刷新
  Widget _buildScrollableMessage(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }

  Widget? _buildBottomBar() {
    if (_selected.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: Text(tr('folderImportConfirm', args: ['${_selected.length}'])),
        ),
      ),
    );
  }
}

class _RawGridTile extends StatefulWidget {
  final String path;
  final bool selected;
  final VoidCallback onTap;
  const _RawGridTile({
    super.key,
    required this.path,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_RawGridTile> createState() => _RawGridTileState();
}

class _RawGridTileState extends State<_RawGridTile>
    with AutomaticKeepAliveClientMixin {
  Future<ui.Image>? _thumbFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _thumbFuture = _loadThumb(widget.path);
  }

  /// 缩略图加载
  Future<ui.Image> _loadThumb(String path) async {
    if (RawFormats.isStandard(path)) {
      // 标准图片：原生解码 + targetWidth
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320);
      final frame = await codec.getNextFrame();
      return frame.image;
    }
    // RAW：LibRaw 内嵌缩略图 → ui.Image
    final raw = await RawBridge.extractThumbnail(path);
    if (raw.isJpegEncoded) {
      final codec = await ui.instantiateImageCodec(raw.pixels as Uint8List);
      return (await codec.getNextFrame()).image;
    }
    // RGB 裸数据 → 补 alpha → ui.Image
    final px = raw.pixels as Uint8List;
    final rgba = Uint8List(raw.width * raw.height * 4);
    for (int i = 0, j = 0; i < px.length; i += 3, j += 4) {
      rgba[j] = px[i];
      rgba[j + 1] = px[i + 1];
      rgba[j + 2] = px[i + 2];
      rgba[j + 3] = 255;
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      raw.width,
      raw.height,
      ui.PixelFormat.rgba8888,
      c.complete,
    );
    return c.future;
  }

  @override
  void dispose() {
    // 释放已解码缩略图
    _thumbFuture?.then((img) => img.dispose()).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnail(),
          _buildBasenameLabel(),
          if (widget.selected) _buildSelectionOverlay(primary),
          _buildCheckCircle(widget.selected, primary),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: AppColors.subtleBorder,
        child: FutureBuilder<ui.Image>(
          future: _thumbFuture,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: AppColors.semanticError.withValues(alpha: 0.5),
                ),
              );
            }
            return RawImage(image: snap.data, fit: BoxFit.cover);
          },
        ),
      ),
    );
  }

  Widget _buildBasenameLabel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: Colors.black.withValues(alpha: 0.5),
        child: Text(
          p.basename(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionOverlay(Color primary) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: primary, width: 3),
        color: primary.withValues(alpha: 0.18),
      ),
    );
  }

  Widget _buildCheckCircle(bool selected, Color primary) {
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? primary : Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.mediumText,
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: AppColors.textPrimary)
            : null,
      ),
    );
  }
}
