import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../services/ai/ai_providers.dart';
import '../services/ai/ai_settings.dart';

class AISettingsDialog extends StatefulWidget {
  const AISettingsDialog({super.key});
  @override
  State<AISettingsDialog> createState() => _AISettingsDialogState();
}

class _AISettingsDialogState extends State<AISettingsDialog> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  AIProviderId _providerId = AISettings.defaultProvider;
  String _modelId = '';
  bool _autoAI = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _providerId = await AISettings.getProvider();
    final key = await AISettings.getApiKey(_providerId);
    _modelId = await AISettings.getModel(_providerId);
    _autoAI = await AISettings.getAutoAI();
    if (mounted) {
      setState(() {
        _keyController.text = key ?? '';
        _loaded = true;
      });
    }
  }

  /// 切换 provider 时：保存当前 provider 的 key，再读新 provider 的配置
  Future<void> _onProviderChanged(AIProviderId? id) async {
    if (id == null || id == _providerId) return;
    await AISettings.setApiKey(_providerId, _keyController.text.trim());
    final newKey = await AISettings.getApiKey(id);
    final newModel = await AISettings.getModel(id);
    if (mounted) {
      setState(() {
        _providerId = id;
        _keyController.text = newKey ?? '';
        _modelId = newModel;
      });
    }
  }

  Future<void> _save() async {
    await AISettings.setProvider(_providerId);
    await AISettings.setApiKey(_providerId, _keyController.text.trim());
    await AISettings.setModel(_providerId, _modelId);
    await AISettings.setAutoAI(_autoAI);
    if (mounted) Navigator.pop(context, true);
  }

  String _keyHintFor(AIProviderId id) => switch (id) {
    AIProviderId.anthropic => 'sk-ant-api03-...',
    AIProviderId.openai => 'sk-proj-... / sk-...',
    AIProviderId.deepseek => 'sk-...',
  };

  String _keyOriginFor(AIProviderId id) => switch (id) {
    AIProviderId.anthropic => tr("getAnthropicKeyFromPlatform"),
    AIProviderId.openai => tr("getOpenaiKeyFromPlatform"),
    AIProviderId.deepseek => tr("getDeepseekKeyFromPlatform"),
  };

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const AlertDialog(
        content: SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
      );
    }
    final provider = AIProvider.byId(_providerId);
    final modelInList = provider.models.any((m) => m.id == _modelId);
    final effectiveModelId = modelInList ? _modelId : provider.defaultModelId;

    return AlertDialog(
      title: Text(tr("aiColorSettings")),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // —— 1. Provider —— //
            Text(tr("aiProvider"),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<AIProviderId>(
              value: _providerId,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: AIProvider.all
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.displayName, style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              onChanged: _onProviderChanged,
            ),
            const SizedBox(height: 14),

            // —— 2. Model —— //
            Text(tr("model"),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: effectiveModelId,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: provider.models
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _modelId = v ?? provider.defaultModelId),
            ),
            const SizedBox(height: 14),

            // —— 3. API Key —— //
            Text('${provider.displayName} ${tr("apiKey")}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _keyController,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: _keyHintFor(_providerId),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 16),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Text(
              _keyOriginFor(_providerId),
              style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
            ),

            const Divider(height: 28),

            // —— 联机自动建议 —— //
            InkWell(
              onTap: () => setState(() => _autoAI = !_autoAI),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _autoAI,
                      onChanged: (v) => setState(() => _autoAI = v ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr("aiColorSuggestionTetherAuto"),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text(
                            tr("aiColorSuggestionTetherAutoDescription"),
                            style: TextStyle(fontSize: 10.5, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr("cancel"))),
        FilledButton(onPressed: _save, child: Text(tr("save"))),
      ],
    );
  }
}