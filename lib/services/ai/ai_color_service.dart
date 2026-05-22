import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import '../../core/models/local_params.dart';
import '../../core/models/mask_shape.dart';
import '../../core/models/adjustment_params.dart';
import '../../core/models/local_adjustment.dart';
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

class AILocalSuggestion {
  final MaskShape mask;
  final LocalParams params;
  final String reason;

  AILocalSuggestion({
    required this.mask,
    required this.params,
    required this.reason,
  });

  factory AILocalSuggestion.fromJson(Map<String, dynamic> j) {
    final type = j['maskType'] as String;
    final shapeJson = Map<String, dynamic>.from(j['maskShape'] as Map);
    shapeJson['type'] = type;
    return AILocalSuggestion(
      mask: MaskShape.fromJson(shapeJson),
      params: LocalParams.fromJson(
        (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      reason: j['reason'] as String? ?? '',
    );
  }
}

class AIColorSuggestion {
  final String reasoning;
  final String mood;
  final Map<String, num?> raw;
  final Map<String, dynamic>? hslRaw;
  final List<AILocalSuggestion> localSuggestions;

  AIColorSuggestion({
    required this.reasoning,
    required this.mood,
    required this.raw,
    this.hslRaw,
    this.localSuggestions = const [],
  });

  List<String> get changedFields {
    final out = <String>[];
    for (final e in raw.entries) {
      if (e.value != null) out.add(e.key);
    }
    if (_hasHslChanges()) out.add('hsl');
    if (localSuggestions.isNotEmpty) {
      out.add('locals(${localSuggestions.length})');
    }
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

    // HSL bands
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

    const maxLocals = 4;
    List<LocalAdjustment> newLocals = cur.locals;
    if (localSuggestions.isNotEmpty) {
      final aiLocals = <LocalAdjustment>[];
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (var k = 0; k < localSuggestions.length; k++) {
        final sug = localSuggestions[k];
        aiLocals.add(
          LocalAdjustment(
            id: 'ai_m_${ts}_$k',
            name: sug.reason.isEmpty
                ? tr("aiLocalAdjustmentEmpty", args: ["${k + 1}"])
                : tr("aiLocalAdjustmentNotEmpty", args: [(sug.reason)]),
            mask: sug.mask,
            params: sug.params,
          ),
        );
      }
      newLocals = [...cur.locals, ...aiLocals].take(maxLocals).toList();
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
      locals: newLocals,
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
      throw AIException(
        tr("aiColorSuggestionLackApiKey", args: [provider.displayName]),
      );
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
      orElse: () => throw AIException(tr("aiColorSuggestionLackTextBlock")),
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
    if (choices.isEmpty) throw AIException(tr("aiColorSuggestionLackChoices"));
    final content = choices.first['message']?['content'];
    if (content is! String || content.isEmpty) {
      throw AIException(tr("aiColorSuggestionLackContent"));
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
    throw AIException(tr("aiColorSuggestionApiKeyError", args: [msg]));
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
      throw AIException(tr("aiColorSuggestionUndecodedResponse", args: [text]));
    }

    final adjMap = obj['adjustments'];
    if (adjMap is! Map) {
      throw AIException(tr("aiColorSuggestionLackAdjustments"));
    }

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
      localSuggestions:
          (obj['localSuggestions'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => AILocalSuggestion.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const [],
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

You may ALSO suggest local adjustments (mask-based regional edits) when the image has clear
regional differences global adjustments can't fix (e.g. blown-out sky + dark foreground).
If not needed, leave "localSuggestions" as an empty array.

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
  },
  "localSuggestions": [
    {
      "maskType": "linear",
      "maskShape": {
        "startX": 0.0..1.0, "startY": 0.0..1.0,
        "endX": 0.0..1.0,   "endY": 0.0..1.0
      },
      "params": {
        "exposure": -3..3, "contrast": -100..100,
        "highlights": -100..100, "shadows": -100..100,
        "whites": -100..100, "blacks": -100..100,
        "temperatureShift": -3000..3000,
        "tint": -100..100, "saturation": -100..100, "vibrance": -100..100
      },
      "reason": "short Chinese / English label, e.g. '压暗天空'"
    },
    {
      "maskType": "radial",
      "maskShape": {
        "centerX": 0.0..1.0, "centerY": 0.0..1.0,
        "radiusX": 0.0..1.0, "radiusY": 0.0..1.0,
        "rotation": -3.14..3.14,
        "feather": 0.0..1.0,
        "inverted": false
      },
      "params": { "exposure": 0.4 },
      "reason": "提亮主体"
    }
  ]
}

Guidelines:
- Tasteful first: small adjustments (±5-25) usually look better than aggressive ones
- HSL is your scalpel — use it for: skin (orange S/L), sky (blue/aqua S), foliage (green/yellow H/S)
- Don't change temperature/tint unless WB is clearly off — current value is user's choice
- Omit the entire "hsl" block (or use all nulls) if no per-color work is needed
- Match scene's natural mood unless user requests otherwise

Local adjustment rules:
- At most 3 entries in localSuggestions; empty array means "no need"
- Coordinates / radii are normalized [0..1] in the cropped output space (top-left origin)
- Linear gradient: alpha smoothly ramps 0→1 from start to end point
- Radial gradient: alpha=1 inside the (possibly rotated) ellipse, 0 outside; feather softens edge
- All params fields are optional (default 0); never include HSL or LUT in local params
- Only suggest locals for clearly regional issues (blown sky, dark subject, distracting bright corner)
- Don't repeat what global adjustments already fixed
''';
  }
}
