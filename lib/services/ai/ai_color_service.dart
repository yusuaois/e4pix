import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/models/adjustment_params.dart';
import '../../core/models/hsl_bands.dart';
import 'ai_providers.dart';
import 'ai_settings.dart';

class AIException implements Exception {
  final String message;
  AIException(this.message);
  @override
  String toString() => message;
}

const _hslBandNames = [
  'red',
  'orange',
  'yellow',
  'green',
  'aqua',
  'blue',
  'purple',
  'magenta',
];

class AIColorSuggestion {
  final String reasoning;
  final String mood;
  final Map<String, num?> raw;
  final Map<String, dynamic>? hslRaw;

  AIColorSuggestion({
    required this.reasoning,
    required this.mood,
    required this.raw,
    this.hslRaw,
  });

  List<String> get changedFields {
    final out = <String>[];
    for (final e in raw.entries) {
      if (e.value != null) out.add(e.key);
    }
    if (_hasHslChanges()) out.add('hsl');
    return out;
  }

  bool _hasHslChanges() {
    if (hslRaw == null) return false;
    for (final v in hslRaw!.values) {
      if (v is Map) {
        for (final iv in v.values) {
          if (iv is num) return true;
        }
      }
    }
    return false;
  }

  AdjustmentParams applyTo(AdjustmentParams cur) {
    double? d(String k) => (raw[k])?.toDouble();
    int? i(String k) => (raw[k])?.toInt();

    // HSL bands (immutable -- chain setters)
    HslBands newHsl = cur.hsl;
    if (hslRaw != null) {
      for (int idx = 0; idx < _hslBandNames.length; idx++) {
        final band = hslRaw![_hslBandNames[idx]];
        if (band is! Map) continue;
        if (band['h'] is num) {
          newHsl = newHsl.setHue(
            idx,
            (band['h'] as num).toDouble().clamp(-100.0, 100.0),
          );
        }
        if (band['s'] is num) {
          newHsl = newHsl.setSat(
            idx,
            (band['s'] as num).toDouble().clamp(-100.0, 100.0),
          );
        }
        if (band['l'] is num) {
          newHsl = newHsl.setLum(
            idx,
            (band['l'] as num).toDouble().clamp(-100.0, 100.0),
          );
        }
      }
    }

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
      hsl: newHsl,
    );
  }
}

class AIColorService {
  static const _anthropicVersion = '2023-06-01';

  static Future<AIColorSuggestion> suggest({
    required Uint8List imageBytes,
    required AdjustmentParams currentParams,
    String? userIntent,
    String mediaType = 'image/jpeg',
  }) async {
    final providerId = await AISettings.getProvider();
    final provider = AIProvider.byId(providerId);
    final apiKey = await AISettings.getApiKey(providerId);
    if (apiKey == null || apiKey.isEmpty) {
      throw AIException('请先在 AI 设置中配置 ${provider.displayName} 的 API key');
    }
    final model = await AISettings.getModel(providerId);
    final base64Image = base64Encode(imageBytes);
    final prompt = _buildPrompt(currentParams, userIntent);

    final text = provider.usesAnthropicFormat
        ? await _callAnthropic(
            provider,
            apiKey,
            model,
            prompt,
            base64Image,
            mediaType,
          )
        : await _callOpenAI(
            provider,
            apiKey,
            model,
            prompt,
            base64Image,
            mediaType,
          );

    return _parseResponse(text);
  }

  // ============================================================
  // Anthropic format（Anthropic 和 DeepSeek/anthropic）
  // ============================================================
  static Future<String> _callAnthropic(
    AIProvider provider,
    String apiKey,
    String model,
    String prompt,
    String base64Image,
    String mediaType,
  ) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 2048,
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
        },
      ],
    };

    if (provider.id == AIProviderId.deepseek) {
      body['thinking'] = {'type': 'disabled'};
    }

    final res = await http
        .post(
          Uri.parse(provider.endpoint),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': _anthropicVersion,
            'content-type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    _checkStatus(res);
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    final blocks = json['content'] as List;
    final textBlock = blocks.cast<Map>().firstWhere(
      (b) => b['type'] == 'text',
      orElse: () => throw AIException('API 响应缺少 text block'),
    );
    return textBlock['text'] as String;
  }

  // ============================================================
  // OpenAI format
  // ============================================================
  static Future<String> _callOpenAI(
    AIProvider provider,
    String apiKey,
    String model,
    String prompt,
    String base64Image,
    String mediaType,
  ) async {
    final res = await http
        .post(
          Uri.parse(provider.endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 2048,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:$mediaType;base64,$base64Image'},
                  },
                  {'type': 'text', 'text': prompt},
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    _checkStatus(res);
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    final choices = json['choices'] as List;
    if (choices.isEmpty) throw AIException('API 响应 choices 为空');
    final content = choices.first['message']?['content'];
    if (content is! String || content.isEmpty) {
      throw AIException('API 响应 content 为空');
    }
    return content;
  }

  static void _checkStatus(http.Response res) {
    if (res.statusCode == 200) return;
    String msg = 'HTTP ${res.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      msg = (j['error']?['message'])?.toString() ?? msg;
    } catch (_) {}
    throw AIException('API 错误: $msg');
  }

  // ============================================================
  // Response parsing
  // ============================================================
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

    final hslMap = obj['hsl'];

    return AIColorSuggestion(
      reasoning: (obj['reasoning'] as String?) ?? '',
      mood: (obj['mood'] as String?) ?? '',
      raw: Map<String, num?>.fromEntries(
        adjMap.entries.map(
          (e) => MapEntry(
            e.key.toString(),
            e.value is num ? e.value as num : null,
          ),
        ),
      ),
      hslRaw: hslMap is Map ? Map<String, dynamic>.from(hslMap) : null,
    );
  }

  // ============================================================
  // Prompt
  // ============================================================
  static String _buildPrompt(AdjustmentParams cur, String? intent) {
    final intentLine = (intent != null && intent.trim().isNotEmpty)
        ? '\n\nUser intent: "${intent.trim()}"'
        : '';

    final h = cur.hsl;
    final hslBlock = StringBuffer();
    for (int i = 0; i < 8; i++) {
      hslBlock.writeln(
        '  ${_hslBandNames[i].padRight(8)}: '
        'H=${h.hues[i].toInt().toString().padLeft(4)}, '
        'S=${h.sats[i].toInt().toString().padLeft(4)}, '
        'L=${h.lums[i].toInt().toString().padLeft(4)}',
      );
    }

    return '''
You are an expert photo colorist analyzing a RAW preview rendered with these CURRENT settings:

[Light & Color]
- Exposure: ${cur.exposure.toStringAsFixed(2)} EV
- Contrast: ${cur.contrast.toInt()}
- Highlights: ${cur.highlights.toInt()}
- Shadows: ${cur.shadows.toInt()}
- Whites: ${cur.whites.toInt()}
- Blacks: ${cur.blacks.toInt()}
- Temperature: ${cur.temperature} K
- Tint: ${cur.tint.toInt()}
- Saturation: ${cur.saturation.toInt()}
- Vibrance: ${cur.vibrance.toInt()}

[HSL bands] (each band: H=hue shift, S=saturation, L=luminance; range -100..100)
$hslBlock$intentLine

Suggest ABSOLUTE values (not deltas). Use `null` for sliders you don't want to touch.

Respond with ONLY a JSON object — no markdown fences, no prose outside JSON:
{
  "reasoning": "1-2 sentences. Use Simplified Chinese if user intent is in Chinese, else English.",
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
  },
  "hsl": {
    "red":     {"h": null or -100..100, "s": null or -100..100, "l": null or -100..100},
    "orange":  {"h": ..., "s": ..., "l": ...},
    "yellow":  {"h": ..., "s": ..., "l": ...},
    "green":   {"h": ..., "s": ..., "l": ...},
    "aqua":    {"h": ..., "s": ..., "l": ...},
    "blue":    {"h": ..., "s": ..., "l": ...},
    "purple":  {"h": ..., "s": ..., "l": ...},
    "magenta": {"h": ..., "s": ..., "l": ...}
  }
}

Guidelines:
- Tasteful first: small adjustments (±5-25) usually look better than aggressive ones
- HSL is your scalpel — use it for: skin (orange S/L), sky (blue/aqua S), foliage (green/yellow H/S)
- Don't change temperature/tint unless WB is clearly off — current value is user's choice
- Omit the entire "hsl" block (or use all nulls) if no per-color work is needed
- Match scene's natural mood unless user requests otherwise
''';
  }
}
