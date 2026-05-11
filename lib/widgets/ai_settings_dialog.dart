import 'package:flutter/material.dart';
import '../services/ai/ai_settings.dart';

class AISettingsDialog extends StatefulWidget {
  const AISettingsDialog({super.key});
  @override
  State<AISettingsDialog> createState() => _AISettingsDialogState();
}

class _AISettingsDialogState extends State<AISettingsDialog> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  String _model = AISettings.defaultModel;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await AISettings.getApiKey();
    final model = await AISettings.getModel();
    if (mounted) {
      setState(() {
        _keyController.text = key ?? '';
        _model = model;
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AISettings.setApiKey(_keyController.text.trim());
    await AISettings.setModel(_model);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const AlertDialog(
        content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      );
    }
    return AlertDialog(
      title: const Text('AI 设置'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Anthropic API Key',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _keyController,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: 'sk-...',
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 16),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 6),
            Text('从 console.anthropic.com 获取',
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 16),
            const Text('Model',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _model,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'deepseek-v4-flash',
                    child: Text('DeepSeek V4 Flash  ·  推荐', style: TextStyle(fontSize: 12))),
                DropdownMenuItem(
                    value: 'deepseek-v4-pro',
                    child: Text('DeepSeek V4 Pro  ·  最强', style: TextStyle(fontSize: 12))),
              ],
              onChanged: (v) => setState(() => _model = v ?? AISettings.defaultModel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}