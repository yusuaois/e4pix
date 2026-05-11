import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/models/adjustment_params.dart';
import 'ai_settings.dart';

class AIException implements Exception {
  final String message;
  AIException(this.message);
  @override
  String toString() => message;
}

class AIColorSuggestion {
  final String reasoning;
  final String mood;
  final Map<String, num?> raw; // 原始 JSON adjustments

  AIColorSuggestion({
    required this.reasoning,
    required this.mood,
    required this.raw,
  });

  /// 把建议套用到现有 params 上，null 字段保留不变
  AdjustmentParams applyTo(AdjustmentParams cur) {
    double? d(String k) => (raw[k] as num?)?.toDouble();
    int? i(String k) => (raw[k] as num?)?.toInt();
    return cur.copyWith(
      exposure: d('exposure') ?? cur.exposure,
      contrast: d('contrast') ?? cur.contrast,
      highlights: d('highlights') ?? cur.highlights,
      shadows: d('shadows') ?? cur.shadows,
      whites: d('whites') ?? cur.whites,
      blacks: d('blacks') ?? cur.blacks,
      temperature: i('temperature') ?? cur.temperature,
      tint: d('tint') ?? cur.tint,
      saturation: d('saturation') ?? cur.saturation,
      vibrance: d('vibrance') ?? cur.vibrance,
    );
  }
}

class AIColorService {
  // deepseek
  static const _endpoint = 'https://api.deepseek.com/anthropic/v1/messages';
  static const _apiVersion = '2023-06-01';

  /// 图片字节 + 当前参数 → AI 建议
  static Future<AIColorSuggestion> suggest({
    required Uint8List imageBytes,
    required AdjustmentParams currentParams,
    String? userIntent,
    String mediaType = 'image/jpeg',
  }) async {
    final apiKey = await AISettings.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw AIException('请先在 AI 设置中配置 Anthropic API key');
    }

    final model = await AISettings.getModel();
    final base64Image = base64Encode(imageBytes);
    final prompt = _buildPrompt(currentParams, userIntent);

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': _apiVersion,
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 1024,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': mediaType,
                      'data': base64Image,
                    },
                  },
                  {'type': 'text', 'text': prompt},
                ],
              }
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final j = jsonDecode(utf8.decode(response.bodyBytes));
        msg = (j['error']?['message'])?.toString() ?? msg;
      } catch (_) {}
      throw AIException('API 错误: $msg');
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    final blocks = json['content'] as List;
    final textBlock = blocks.cast<Map>().firstWhere(
          (b) => b['type'] == 'text',
          orElse: () => throw AIException('API 响应为空'),
        );
    return _parseResponse(textBlock['text'] as String);
  }

  static AIColorSuggestion _parseResponse(String text) {
    String cleaned = text.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final m = fence.firstMatch(cleaned);
    if (m != null) cleaned = m.group(1)!.trim();

    final Map<String, dynamic> obj;
    try {
      obj = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw AIException('无法解析 AI 响应:\n$text');
    }

    final adjMap = obj['adjustments'];
    if (adjMap is! Map) throw AIException('AI 响应缺少 adjustments 字段');

    return AIColorSuggestion(
      reasoning: (obj['reasoning'] as String?) ?? '',
      mood: (obj['mood'] as String?) ?? '',
      raw: Map<String, num?>.fromEntries(
        adjMap.entries.map((e) => MapEntry(
              e.key.toString(),
              e.value is num ? e.value as num : null,
            )),
      ),
    );
  }

  static String _buildPrompt(AdjustmentParams cur, String? intent) {
    final intentLine = (intent != null && intent.trim().isNotEmpty)
        ? '\n\nUser intent: "${intent.trim()}"'
        : '';

    return '''
You are an expert photo colorist analyzing a RAW preview rendered with these current settings:
- Exposure: ${cur.exposure.toStringAsFixed(2)} EV
- Contrast: ${cur.contrast.toInt()}
- Highlights: ${cur.highlights.toInt()}
- Shadows: ${cur.shadows.toInt()}
- Whites: ${cur.whites.toInt()}
- Blacks: ${cur.blacks.toInt()}
- Temperature: ${cur.temperature} K
- Tint: ${cur.tint.toInt()}
- Saturation: ${cur.saturation.toInt()}
- Vibrance: ${cur.vibrance.toInt()}$intentLine

Suggest ABSOLUTE values (not deltas) for each slider that would best serve this image. Use `null` for sliders you don't want to change.

Respond with ONLY a JSON object — no markdown, no prose outside JSON:
{
  "reasoning": "1-2 sentences explaining the look. Use Simplified Chinese if user intent is in Chinese, otherwise English.",
  "mood": "short label like 'natural daylight' or '电影感暖调'",
  "adjustments": {
    "exposure": null or -5..5,
    "contrast": null or -100..100,
    "highlights": null or -100..100,
    "shadows": null or -100..100,
    "whites": null or -100..100,
    "blacks": null or -100..100,
    "temperature": null or 2000..12000,
    "tint": null or -100..100,
    "saturation": null or -100..100,
    "vibrance": null or -100..100
  }
}

Guidelines:
- Tasteful: small adjustments (±5-20) often look better than aggressive ones (±50+)
- Match the scene's natural mood unless user requests otherwise
- Don't change temperature/tint unless WB is clearly off — current value is the user's choice
- Push shadows/highlights for dynamic range, contrast for punch
- Vibrance > saturation for skin tones
''';
  }
}