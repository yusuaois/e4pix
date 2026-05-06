import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/camera/camera_controller.dart';

class CameraPickResult {
  final DetectedCamera camera;
  final String saveFolder;
  CameraPickResult(this.camera, this.saveFolder);
}

class CameraPickerDialog extends StatefulWidget {
  final CameraController controller;
  const CameraPickerDialog({super.key, required this.controller});

  @override
  State<CameraPickerDialog> createState() => _CameraPickerDialogState();
}

class _CameraPickerDialogState extends State<CameraPickerDialog> {
  List<DetectedCamera> _cameras = [];
  DetectedCamera? _selected;
  String? _folder;
  bool _detecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final list = await widget.controller.detectCameras();
      setState(() {
        _cameras = list;
        _selected = list.isNotEmpty ? list.first : null;
        _detecting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _detecting = false;
      });
    }
  }

  Future<void> _pickFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存文件夹',
    );
    if (folder != null) setState(() => _folder = folder);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('联机拍摄'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('已检测到的相机',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: '重新探测',
                  onPressed: _detecting ? null : _detect,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minHeight: 70),
              child: _detecting
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _error != null
                      ? Text(_error!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.redAccent))
                      : _cameras.isEmpty
                          ? Text(
                              '未发现相机。\n'
                              '· Windows: 检查 usbipd attach 是否已挂载\n'
                              // usbipd list  
                              // usbipd attach --wsl --busid <busid>
                              '· Linux/macOS: 检查 USB 线 + 相机是否处于 Tether 模式',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.6)))
                          : Column(
                              children: _cameras.map((c) {
                                final isSel = c == _selected;
                                return InkWell(
                                  onTap: () =>
                                      setState(() => _selected = c),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSel
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                          size: 14,
                                          color: isSel
                                              ? const Color(0xFF6B5BFF)
                                              : Colors.white.withOpacity(0.4),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            c.model,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        Text(
                                          c.port,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                            color:
                                                Colors.white.withOpacity(0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
            ),
            const SizedBox(height: 14),
            const Text('保存到',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E0E14),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Text(
                      _folder ?? '未选择',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: _folder == null
                            ? Colors.white.withOpacity(0.4)
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _pickFolder,
                  child: const Text('浏览'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (_selected != null && _folder != null)
              ? () => Navigator.pop(
                    context,
                    CameraPickResult(_selected!, _folder!),
                  )
              : null,
          child: const Text('开始联机'),
        ),
      ],
    );
  }
}