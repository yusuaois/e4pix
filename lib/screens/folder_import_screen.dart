import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/constants/raw_formats.dart';
import '../native/raw_bridge.dart';

Future<List<String>?> openFolderImport(BuildContext context) async {
  final dir = await FilePicker.platform.getDirectoryPath(
    dialogTitle: tr('folderImportPickDir'),
  );
  if (dir == null || dir.isEmpty || dir == '/') return null;
  if (!context.mounted) return null;

  return Navigator.of(context).push<List<String>>(
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
        if (e is File && RawFormats.isRaw(e.path)) {
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
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0E),
        title: Text(
          p.basename(widget.dirPath),
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (_rawPaths.isNotEmpty)
            TextButton(
              onPressed: allSelected ? _selectNone : _selectAll,
              child: Text(
                allSelected ? tr('deselectAll') : tr('selectAll'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            )
          : _rawPaths.isEmpty
          ? Center(
              child: Text(
                tr('folderImportEmpty'),
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
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
            ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected.toList()),
                  child: Text(
                    tr('folderImportConfirm', args: ['${_selected.length}']),
                  ),
                ),
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
  Future<RawDecodedImage>? _thumbFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _thumbFuture = RawBridge.extractThumbnail(widget.path);
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
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              color: Colors.white.withValues(alpha: 0.04),
              child: FutureBuilder<RawDecodedImage>(
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
                        color: Colors.redAccent.withValues(alpha: 0.5),
                      ),
                    );
                  }
                  return _ThumbImage(raw: snap.data!);
                },
              ),
            ),
          ),
          Positioned(
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
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
          if (widget.selected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primary, width: 3),
                color: primary.withValues(alpha: 0.18),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.selected
                    ? primary
                    : Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: widget.selected ? 1 : 0.6,
                  ),
                  width: 1.5,
                ),
              ),
              child: widget.selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbImage extends StatefulWidget {
  final RawDecodedImage raw;
  const _ThumbImage({required this.raw});
  @override
  State<_ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<_ThumbImage> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final raw = widget.raw;
    ui.Image? img;
    try {
      if (raw.isJpegEncoded) {
        final codec = await ui.instantiateImageCodec(raw.pixels as Uint8List);
        img = (await codec.getNextFrame()).image;
      } else if (raw.pixels is Uint8List) {
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
        img = await c.future;
      }
    } catch (_) {}
    if (!mounted) {
      img?.dispose();
      return;
    }
    setState(() => _img = img);
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_img == null) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    return RawImage(image: _img, fit: BoxFit.cover);
  }
}
