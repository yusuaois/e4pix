enum AIProtocol { anthropic, openai }

class AIModelOption {
  final String id;
  final String label;
  const AIModelOption(this.id, this.label);
}

class AIProviderPreset {
  final String id;
  final String displayName;
  final AIProtocol protocol;
  final String? defaultEndpoint;
  final bool requiresEndpoint;
  final bool requiresApiKey;
  final bool allowsCustomModels;
  final List<AIModelOption> preconfiguredModels;
  final String defaultModelId;
  final String? apiKeyHint;
  final String? apiKeyOriginTrKey;
  final Map<String, dynamic>? extraRequestBody;

  const AIProviderPreset({
    required this.id,
    required this.displayName,
    required this.protocol,
    this.defaultEndpoint,
    this.requiresEndpoint = false,
    this.requiresApiKey = true,
    this.allowsCustomModels = false,
    this.preconfiguredModels = const [],
    required this.defaultModelId,
    this.apiKeyHint,
    this.apiKeyOriginTrKey,
    this.extraRequestBody,
  });

  // ── 预设 ──

  static const _anthropic = AIProviderPreset(
    id: 'anthropic',
    displayName: 'Anthropic Claude',
    protocol: AIProtocol.anthropic,
    defaultEndpoint: 'https://api.anthropic.com/v1/messages',
    defaultModelId: 'claude-sonnet-4-6',
    apiKeyHint: 'sk-ant-api03-...',
    apiKeyOriginTrKey: 'getAnthropicKeyFromPlatform',
    preconfiguredModels: [
      AIModelOption('claude-sonnet-4-6', 'Claude Sonnet 4.6'),
      AIModelOption('claude-opus-4-7', 'Claude Opus 4.7'),
      AIModelOption('claude-haiku-4-5-20251001', 'Claude Haiku 4.5'),
    ],
  );

  static const _openai = AIProviderPreset(
    id: 'openai',
    displayName: 'OpenAI',
    protocol: AIProtocol.openai,
    defaultEndpoint: 'https://api.openai.com/v1/chat/completions',
    defaultModelId: 'gpt-4o',
    apiKeyHint: 'sk-proj-... / sk-...',
    apiKeyOriginTrKey: 'getOpenaiKeyFromPlatform',
    preconfiguredModels: [
      AIModelOption('gpt-4o', 'GPT-4o'),
      AIModelOption('gpt-4o-mini', 'GPT-4o mini'),
      AIModelOption('gpt-4-turbo', 'GPT-4 Turbo'),
    ],
  );

  static const _deepseek = AIProviderPreset(
    id: 'deepseek',
    displayName: 'DeepSeek',
    protocol: AIProtocol.anthropic,
    defaultEndpoint: 'https://api.deepseek.com/anthropic/v1/messages',
    defaultModelId: 'deepseek-v4-flash',
    apiKeyHint: 'sk-...',
    apiKeyOriginTrKey: 'getDeepseekKeyFromPlatform',
    extraRequestBody: {
      'thinking': {'type': 'disabled'},
    },
    preconfiguredModels: [
      AIModelOption('deepseek-v4-flash', 'DeepSeek V4 Flash'),
      AIModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro'),
    ],
  );

  static const _openrouter = AIProviderPreset(
    id: 'openrouter',
    displayName: 'OpenRouter',
    protocol: AIProtocol.openai,
    defaultEndpoint: 'https://openrouter.ai/api/v1/chat/completions',
    defaultModelId: 'openai/gpt-4o',
    allowsCustomModels: true,
    apiKeyHint: 'sk-or-v1-...',
    apiKeyOriginTrKey: 'getOpenRouterKeyFromPlatform',
    preconfiguredModels: [
      AIModelOption('openai/gpt-4o', 'GPT-4o'),
      AIModelOption('anthropic/claude-sonnet-4-6', 'Claude Sonnet 4.6'),
      AIModelOption('google/gemini-2.5-pro', 'Gemini 2.5 Pro'),
      AIModelOption('meta-llama/llama-4-maverick', 'Llama 4 Maverick'),
    ],
  );

  static const _customOpenAI = AIProviderPreset(
    id: 'custom_openai',
    displayName: 'Custom (OpenAI Compat.)',
    protocol: AIProtocol.openai,
    requiresEndpoint: true,
    allowsCustomModels: true,
    defaultModelId: '',
    apiKeyHint: 'sk-...',
    apiKeyOriginTrKey: 'aiCustomGetKeyFrom',
  );

  static const _customAnthropic = AIProviderPreset(
    id: 'custom_anthropic',
    displayName: 'Custom (Anthropic Compat.)',
    protocol: AIProtocol.anthropic,
    requiresEndpoint: true,
    allowsCustomModels: true,
    defaultModelId: '',
    apiKeyHint: 'sk-...',
    apiKeyOriginTrKey: 'aiCustomGetKeyFrom',
  );

  // ============================================================
  // Registry
  // ============================================================

  static const all = <AIProviderPreset>[
    _anthropic,
    _openai,
    _deepseek,
    _openrouter,
    _customOpenAI,
    _customAnthropic,
  ];

  static AIProviderPreset byId(String id) => all.firstWhere((p) => p.id == id);

  /// Returns null if [id] is unknown, instead of throwing.
  static AIProviderPreset? safeById(String? id) {
    if (id == null) return null;
    try {
      return byId(id);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // Migration from old AIProviderId enum
  // 【可删除】下个大版本清理：_oldEnumToPresetId + migrateOldEnumName()
  // ============================================================

  static const _oldEnumToPresetId = <String, String>{
    'anthropic': 'anthropic',
    'openai': 'openai',
    'deepseek': 'deepseek',
    // 'custom' maps to sentinel — handled by AISettings._migrateOldCustom
  };

  /// Returns null if [stored] is not a recognized old enum name.
  /// Returns '__needs_custom_migration__' sentinel for old 'custom'.
  /// 【可删除】与 _oldEnumToPresetId 一起删
  static String? migrateOldEnumName(String stored) {
    if (_oldEnumToPresetId.containsKey(stored)) {
      return _oldEnumToPresetId[stored];
    }
    if (stored == 'custom') return '__needs_custom_migration__';
    return null;
  }
}
