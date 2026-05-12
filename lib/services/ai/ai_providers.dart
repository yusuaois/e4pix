enum AIProviderId { anthropic, openai, deepseek }

class AIModelOption {
  final String id;
  final String label;
  const AIModelOption(this.id, this.label);
}

class AIProvider {
  final AIProviderId id;
  final String displayName;
  final String endpoint;
  final List<AIModelOption> models;
  final String defaultModelId;

  const AIProvider({
    required this.id,
    required this.displayName,
    required this.endpoint,
    required this.models,
    required this.defaultModelId,
  });

  bool get usesAnthropicFormat =>
      id == AIProviderId.anthropic || id == AIProviderId.deepseek;

  static const _anthropic = AIProvider(
    id: AIProviderId.anthropic,
    displayName: 'Anthropic Claude',
    endpoint: 'https://api.anthropic.com/v1/messages',
    defaultModelId: 'claude-sonnet-4-6',
    models: [
      AIModelOption('claude-sonnet-4-6', 'Claude Sonnet 4.6  ·  推荐'),
      AIModelOption('claude-opus-4-7', 'Claude Opus 4.7  ·  最强'),
      AIModelOption('claude-haiku-4-5-20251001', 'Claude Haiku 4.5  ·  最快/最便宜'),
    ],
  );

  static const _openai = AIProvider(
    id: AIProviderId.openai,
    displayName: 'OpenAI',
    endpoint: 'https://api.openai.com/v1/chat/completions',
    defaultModelId: 'gpt-4o',
    models: [
      AIModelOption('gpt-4o', 'GPT-4o  ·  推荐'),
      AIModelOption('gpt-4o-mini', 'GPT-4o mini  ·  便宜'),
      AIModelOption('gpt-4-turbo', 'GPT-4 Turbo'),
    ],
  );

  static const _deepseek = AIProvider(
    id: AIProviderId.deepseek,
    displayName: 'DeepSeek',
    endpoint: 'https://api.deepseek.com/anthropic/v1/messages',
    defaultModelId: 'deepseek-v4-flash',
    models: [
      AIModelOption('deepseek-v4-flash', 'DeepSeek V4 Flash  ·  推荐'),
      AIModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro  ·  最强'),
    ],
  );

  static const all = <AIProvider>[_anthropic, _openai, _deepseek];

  static AIProvider byId(AIProviderId id) =>
      all.firstWhere((p) => p.id == id);
}