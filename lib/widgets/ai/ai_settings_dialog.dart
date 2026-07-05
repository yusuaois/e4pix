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
  String _presetId = AIProviderPreset.all.first.id;
  String _modelId = '';
  bool _useCustomModel = false;
  bool _autoAI = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _presetId = await AISettings.getProvider();
    final preset = AIProviderPreset.byId(_presetId);
    final key = await AISettings.getApiKey(_presetId);
    _modelId = await AISettings.getModel(_presetId);
    _autoAI = await AISettings.getAutoAI();

    if (preset.requiresEndpoint) {
      _endpointController.text = await AISettings.getEndpoint(_presetId);
    }
    if (preset.allowsCustomModels) {
      _customModelController.text = _modelId;
      // 若已保存模型不在预配置列表中，则为用户自定义模型
      if (preset.preconfiguredModels.isNotEmpty &&
          !preset.preconfiguredModels.any((m) => m.id == _modelId)) {
        _useCustomModel = true;
      }
    }
    if (mounted) {
      setState(() {
        _keyController.text = key ?? '';
        _loaded = true;
      });
    }
  }

  /// Save data for the currently selected preset (without changing provider).
  Future<void> _saveCurrentPreset() async {
    final preset = AIProviderPreset.byId(_presetId);
    await AISettings.setApiKey(_presetId, _keyController.text.trim());
    if (preset.requiresEndpoint) {
      await AISettings.setEndpoint(_presetId, _endpointController.text.trim());
    }
    final effectiveModel = preset.allowsCustomModels
        ? _customModelController.text.trim()
        : _modelId;
    if (effectiveModel.isNotEmpty) {
      await AISettings.setModel(_presetId, effectiveModel);
    }
  }

  /// Switch to a different provider preset.
  Future<void> _onProviderChanged(String? newId) async {
    if (newId == null || newId == _presetId) return;

    // Save old preset's data
    await _saveCurrentPreset();

    // Switch to new preset
    _presetId = newId;
    _useCustomModel = false;
    final preset = AIProviderPreset.byId(newId);

    // Load new preset's data
    final newKey = await AISettings.getApiKey(newId);
    _modelId = await AISettings.getModel(newId);
    if (preset.requiresEndpoint) {
      _endpointController.text = await AISettings.getEndpoint(newId);
    } else {
      _endpointController.clear();
    }
    if (preset.allowsCustomModels) {
      _customModelController.text = _modelId;
      if (preset.preconfiguredModels.isNotEmpty &&
          !preset.preconfiguredModels.any((m) => m.id == _modelId)) {
        _useCustomModel = true;
      }
    } else {
      _customModelController.clear();
    }

    if (mounted) {
      setState(() {
        _keyController.text = newKey ?? '';
      });
    }
  }

  Future<void> _save() async {
    await AISettings.setProvider(_presetId);
    await _saveCurrentPreset();
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

    final preset = AIProviderPreset.byId(_presetId);
    final modelInList = preset.preconfiguredModels.any((m) => m.id == _modelId);
    final effectiveModelId = modelInList ? _modelId : preset.defaultModelId;

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
              DropdownButtonFormField<String>(
                initialValue: _presetId,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                items: AIProviderPreset.all
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

              // —— Endpoint (shown only if preset requires it) —— //
              if (preset.requiresEndpoint) ...[
                Text(
                  tr("aiCustomEndpoint"),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _endpointController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
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
              ],

              // —— 2. Model —— //
              Text(
                tr("model"),
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),

              // Branch A: Standard dropdown only (no custom models allowed)
              if (!preset.allowsCustomModels)
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
                  items: preset.preconfiguredModels
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.label, style: AppTypography.bodyLarge),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _modelId = v ?? preset.defaultModelId),
                )
              // Branch B: Custom models only, no preconfigured list → just text field
              else if (preset.preconfiguredModels.isEmpty) ...[
                Text(
                  tr("aiCustomModel"),
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _customModelController,
                  textInputAction: TextInputAction.next,
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
              ]
              // Branch C: Preconfigured models + "Custom..." option
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _useCustomModel
                      ? '__custom__'
                      : effectiveModelId,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    ...preset.preconfiguredModels.map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.label, style: AppTypography.bodyLarge),
                      ),
                    ),
                    DropdownMenuItem(
                      value: '__custom__',
                      child: Text(tr("aiCustomModelOption")),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == '__custom__') {
                      setState(() {
                        _useCustomModel = true;
                        _customModelController.text = _modelId;
                      });
                    } else {
                      setState(() {
                        _useCustomModel = false;
                        _modelId = v ?? preset.defaultModelId;
                      });
                    }
                  },
                ),
                if (_useCustomModel) ...[
                  const SizedBox(height: 10),
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
                ],
              ],

              const SizedBox(height: 14),

              // —— 3. API Key (shown only if preset requires it) —— //
              if (preset.requiresApiKey) ...[
                Text(
                  '${preset.displayName} ${tr("apiKey")}',
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _keyController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: preset.apiKeyHint ?? 'sk-...',
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
                if (preset.apiKeyOriginTrKey != null)
                  Text(
                    tr(preset.apiKeyOriginTrKey!),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.faintText,
                    ),
                  ),
              ],

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
                            const SizedBox(height: 2),
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
