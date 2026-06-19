import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../services/ai/ai_providers.dart';
import '../../services/ai/ai_settings.dart';

class AISettingsDialog extends StatefulWidget {
  const AISettingsDialog({super.key});
  @override
  State<AISettingsDialog> createState() => _AISettingsDialogState();
}

class _AISettingsDialogState extends State<AISettingsDialog> {
  final _keyController = TextEditingController();
  final _endpointController = TextEditingController();
  final _customModelController = TextEditingController();
  bool _obscure = true;
  AIProviderId _providerId = AISettings.defaultProvider;
  String _modelId = '';
  String _customFormat = 'anthropic';
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
    if (_providerId == AIProviderId.custom) {
      _customFormat = await AISettings.getCustomFormat();
      _endpointController.text = await AISettings.getCustomEndpoint();
      _customModelController.text = _modelId;
    }
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
    if (_providerId == AIProviderId.custom) {
      await AISettings.setCustomEndpoint(_endpointController.text.trim());
      await AISettings.setCustomFormat(_customFormat);
      _modelId = _customModelController.text.trim();
      await AISettings.setModel(_providerId, _modelId);
    } else {
      await AISettings.setApiKey(_providerId, _keyController.text.trim());
      await AISettings.setModel(_providerId, _modelId);
    }
    if (id == AIProviderId.custom) {
      _customFormat = await AISettings.getCustomFormat();
      _endpointController.text = await AISettings.getCustomEndpoint();
      _modelId = await AISettings.getModel(id);
      _customModelController.text = _modelId;
      final newKey = await AISettings.getApiKey(id);
      if (mounted) {
        setState(() {
          _providerId = id;
          _keyController.text = newKey ?? '';
        });
      }
    } else {
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
  }

  Future<void> _save() async {
    await AISettings.setProvider(_providerId);
    await AISettings.setApiKey(_providerId, _keyController.text.trim());
    if (_providerId == AIProviderId.custom) {
      await AISettings.setCustomEndpoint(_endpointController.text.trim());
      await AISettings.setCustomFormat(_customFormat);
      _modelId = _customModelController.text.trim();
      await AISettings.setModel(_providerId, _modelId);
    } else {
      await AISettings.setModel(_providerId, _modelId);
    }
    await AISettings.setAutoAI(_autoAI);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _endpointController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  String _keyHintFor(AIProviderId id) => switch (id) {
    AIProviderId.anthropic => 'sk-ant-api03-...',
    AIProviderId.openai => 'sk-proj-... / sk-...',
    AIProviderId.deepseek => 'sk-...',
    AIProviderId.custom => 'sk-...',
  };

  String _keyOriginFor(AIProviderId id) => switch (id) {
    AIProviderId.anthropic => tr("getAnthropicKeyFromPlatform"),
    AIProviderId.openai => tr("getOpenaiKeyFromPlatform"),
    AIProviderId.deepseek => tr("getDeepseekKeyFromPlatform"),
    AIProviderId.custom => tr("aiCustomGetKeyFrom"),
  };

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final provider = AIProvider.byId(_providerId);
    final modelInList = provider.models.any((m) => m.id == _modelId);
    final effectiveModelId = modelInList ? _modelId : provider.defaultModelId;

    return AlertDialog(
      title: Text(tr("aiColorSettings")),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // —— 1. Provider —— //
              Text(
                tr("aiProvider"),
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<AIProviderId>(
                initialValue: _providerId,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                items: AIProvider.all
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.displayName,
                          style: AppTypography.bodyLarge,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _onProviderChanged,
              ),
              const SizedBox(height: 14),

              if (_providerId == AIProviderId.custom) ...[
                // —— Custom: API Format —— //
                Text(
                  tr("aiCustomFormat"),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _customFormat,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'anthropic',
                      child: Text(
                        tr("aiCustomFormatAnthropic"),
                        style: AppTypography.bodyLarge,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'openai',
                      child: Text(
                        tr("aiCustomFormatOpenAI"),
                        style: AppTypography.bodyLarge,
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _customFormat = v ?? 'anthropic'),
                ),
                const SizedBox(height: 14),

                // —— Custom: Endpoint —— //
                Text(
                  tr("aiCustomEndpoint"),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _endpointController,
                  decoration: InputDecoration(
                    hintText: tr("aiCustomEndpointHint"),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  style: AppTypography.bodyMedium.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 14),

                // —— Custom: Model Name —— //
                Text(
                  tr("aiCustomModel"),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _customModelController,
                  decoration: InputDecoration(
                    hintText: tr("aiCustomModelHint"),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  style: AppTypography.bodyMedium.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ] else ...[
                // —— 2. Model —— //
                Text(
                  tr("model"),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: effectiveModelId,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: provider.models
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.label, style: AppTypography.bodyLarge),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _modelId = v ?? provider.defaultModelId),
                ),
              ],
              const SizedBox(height: 14),

              // —— 3. API Key —— //
              Text(
                _providerId == AIProviderId.custom
                    ? tr("apiKey")
                    : '${provider.displayName} ${tr("apiKey")}',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _keyController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: _keyHintFor(_providerId),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                      size: 16,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                style: AppTypography.bodyMedium.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _keyOriginFor(_providerId),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.faintText,
                ),
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
                            Text(
                              tr("aiColorSuggestionTetherAuto"),
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              tr("aiColorSuggestionTetherAutoDescription"),
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.mediumText,
                              ),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr("cancel")),
        ),
        FilledButton(onPressed: _save, child: Text(tr("save"))),
      ],
    );
  }
}
