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
    final type = j['maskType'] as String?;
    if (type == null) {
      throw AIException('Local suggestion missing maskType');
    }
    final shapeRaw = j['maskShape'];
    if (shapeRaw is! Map) {
      throw AIException('Local suggestion missing or invalid maskShape');
    }
    final shapeJson = Map<String, dynamic>.from(shapeRaw);
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
      exposure: (d('exposure') ?? cur.exposure).clamp(-5.0, 5.0),
      contrast: (d('contrast') ?? cur.contrast).clamp(-100.0, 100.0),
      highlights: (d('highlights') ?? cur.highlights).clamp(-100.0, 100.0),
      shadows: (d('shadows') ?? cur.shadows).clamp(-100.0, 100.0),
      whites: (d('whites') ?? cur.whites).clamp(-100.0, 100.0),
      blacks: (d('blacks') ?? cur.blacks).clamp(-100.0, 100.0),
      temperature: (i('temperature') ?? cur.temperature).clamp(2000, 12000),
      tint: (d('tint') ?? cur.tint).clamp(-100.0, 100.0),
      saturation: (d('saturation') ?? cur.saturation).clamp(-100.0, 100.0),
      vibrance: (d('vibrance') ?? cur.vibrance).clamp(-100.0, 100.0),
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
    String languageCode = 'en',
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
    final prompt = _buildPrompt(currentParams, userIntent, languageCode);

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
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final m = fence.firstMatch(cleaned);
    if (m != null) cleaned = m.group(1)!.trim();

    Map<String, dynamic>? obj;
    try {
      obj = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      final start = cleaned.indexOf('{');
      if (start != -1) {
        final extracted = _extractFirstJsonObject(cleaned.substring(start));
        if (extracted != null) {
          try {
            obj = jsonDecode(extracted) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
      if (obj == null) {
        throw AIException(
          tr("aiColorSuggestionUndecodedResponse", args: [text]),
        );
      }
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
          (e) => MapEntry(e.key.toString(), _coerceNum(e.value)),
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

  /// Coerce a JSON value to [num] or return null.
  /// Handles int, double, and string-encoded numbers (LLMs sometimes quote them).
  static num? _coerceNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// Extract the first balanced JSON object from [s].
  /// Returns null if no complete object is found.
  static String? _extractFirstJsonObject(String s) {
    if (s.isEmpty || s[0] != '{') return null;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return s.substring(0, i + 1);
      }
    }
    return null; // unbalanced braces
  }

  // ============================================================
  // Prompt
  // ============================================================
  static String _buildPrompt(
    AdjustmentParams cur,
    String? intent,
    String languageCode,
  ) {
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

    return _buildPromptV4(
      cur,
      intent,
      hslBlock.toString(),
      intentLine,
      languageCode,
    );
  }

  static String _buildPromptV4(
    AdjustmentParams cur,
    String? intent,
    String hslBlock,
    String intentLine,
    String languageCode,
  ) {
    final hasIntent = intent != null && intent.trim().isNotEmpty;
    final langInstruction = languageCode != 'en'
        ? '\n- ALL text fields (reasoning, mood, reason) MUST be written in language code: $languageCode.'
        : '';
    final intentBlock = hasIntent
        ? '''
<creative_intent>
The user has specified a creative intent: "$intent"

This is the HIGHEST-PRIORITY instruction. Map it to the following parameter philosophy and honor it faithfully:

CINEMATIC / FILM (e.g. "王家卫", "film noir", "moody cinema", "电影感"):
  → Crush blacks (-15 to -30), compress highlights (-10 to -25), reduce global contrast slightly.
  → Lower saturation (-8 to -18) then selectively restore 1-2 key colors via HSL.
  → Add subtle color cast: temperature ±100-250K or tint ±3-8 depending on desired warmth/cool.
  → Local: radial on subject with +0.2 to +0.5 EV lift; optional vignette via inverted radial.

CYBERPUNK / NEON (e.g. "赛博朋克", "neon night", "blade runner"):
  → Cool the base (temperature -200 to -600K), deep blacks (-20 to -35).
  → Blue S +15-30 / L -10-20 for deep night sky; purple S +10-20 for neon atmosphere.
  → Orange/yellow H ±5-8 toward amber + S +10-20 for warm practical-light glow.

JAPANESE SOFT / FILM EMULATION (e.g. "日系", "pastel", "小清新", "フィルム"):
  → Lift blacks gently (+8 to +20), reduce contrast (-10 to -20), soft whites (+5 to +15).
  → Global saturation -8 to -15; vibrance +5 to +10 for selective color retention.
  → HSL: slightly desaturate greens/blues, keep orange (skin/warm tones) natural or +3-5 L.

LANDSCAPE DRAMATIC (e.g. "大气风光", "epic landscape", "dramatic skies"):
  → Recover highlights (-20 to -40), lift shadows (+10 to +25) for HDR-balanced range.
  → Blue S +10-20 / L -10-20 for deeper sky; green S +5-15, H ±5 for foliage richness.
  → Vibrance +10-20 (preferred over saturation for natural scenes).

WARM / GOLDEN (e.g. "暖调", "golden hour", "warm film", "胶片暖"):
  → Temperature +150-350K, tint +3-6.
  → Orange H toward amber (+5-10), S +5-15, L +5-10 for radiant warmth.
  → Highlights -5 to -15 to preserve glow without blowout.

If the intent does not match the above templates exactly, extract the emotional keywords and translate them to parameters that serve the same feeling. Bias toward subtlety.
</creative_intent>
'''
        : '''
<technical_enhancement>
No specific intent provided. Mode: Natural Technical Enhancement.

Goal: Make the image look like the best possible version of its own light and content. Do NOT impose a style or mood.
  1. Correct obvious technical failures only (blown highlights, crushed blacks, clear color casts).
  2. Optimize tonal range to match the scene's natural light character.
  3. Make edits invisible — the viewer should feel the image improved, not edited.
  4. Hard cap on all global sliders: ±25 from current values (except exposure: ±1.5 EV max shift).
</technical_enhancement>
''';

    return '''
<absolute_rules>
OUTPUT ONLY A SINGLE RAW JSON OBJECT.
- NO ```json fences. NO markdown backticks of any kind.
- NO prose, comments, or explanation outside the JSON.
- Every character outside the JSON will crash the production app.$langInstruction
</absolute_rules>

Analyze the provided image first, then review the current parameters below. 
CRITICAL: You must output ABSOLUTE target values for global adjustments (e.g., if current exposure is 1.0 and you want to add 0.5, output 1.5).

## Current Parameters (what the user already set)

[Light & Color]
  Exposure:     ${cur.exposure.toStringAsFixed(2)} EV
  Contrast:     ${cur.contrast.toInt()}
  Highlights:   ${cur.highlights.toInt()}
  Shadows:      ${cur.shadows.toInt()}
  Whites:       ${cur.whites.toInt()}
  Blacks:       ${cur.blacks.toInt()}
  Temperature:  ${cur.temperature} K
  Tint:         ${cur.tint.toInt()}
  Saturation:   ${cur.saturation.toInt()}
  Vibrance:     ${cur.vibrance.toInt()}

[HSL per-band] (H / S / L each in [-100, 100])
$hslBlock$intentLine

---

## STEP 1 — Scene Classification
Classify the primary genre and light quality internally. These MUST dictate your HSL and Local decisions.

## STEP 2 — User Intent
$intentBlock

## STEP 3 — Global Light & Color
- Exposure: Do not touch unless metering is visibly wrong.
- Tone Shaping: Pull highlights only if clipped. Lift shadows only if detail is lost.
- White Balance: Do NOT adjust minor intentional casts. Correct only objective errors.

## STEP 4 — HSL: Color Precision Work
Only modify bands that have a meaningful visual role in THIS specific image. 
- HSL Constraints: Hue shift max ±15 (unless artistic). Saturation max ±30.
- If color balance is already perfect, leave values as null.

## STEP 5 — Local Adjustments: Spatial Light Sculpting
Use local adjustments ONLY to redirect viewer attention or fix regional problems (Max 3).

### SPATIAL COORDINATE SYSTEM
- Normalized screen coordinate system [0.0 to 1.0].
- X-axis: 0.0 is Left, 1.0 is Right.
- Y-axis: 0.0 is TOP, 1.0 is BOTTOM. (A dark sky at the top means startY: 0.0 to endY: 0.4).

### Mask Types
- "linear": Best for horizon splits. Requires startX, startY, endX, endY.
- "radial": Best for isolating subjects or vignettes. Requires centerX, centerY, radiusX, radiusY, rotation, feather, inverted (boolean).

---

## JSON Output Schema

{
  "reasoning": "1-2 sentences: scene type, light character, main edit direction.",
  "mood": "Short creative label.",
  "adjustments": {
    "exposure":    null, // or absolute float
    "contrast":    null, // or absolute integer [-100, 100]
    "highlights":  null, // or absolute integer [-100, 100]
    "shadows":     null, // or absolute integer [-100, 100]
    "whites":      null, // or absolute integer [-100, 100]
    "blacks":      null, // or absolute integer [-100, 100]
    "temperature": null, // or absolute integer [2000, 12000]
    "tint":        null, // or absolute integer [-100, 100]
    "saturation":  null, // or absolute integer [-100, 100]
    "vibrance":    null  // or absolute integer [-100, 100]
  },
  "hsl": {
    "red":     {"h": null, "s": null, "l": null}, // null or integer [-100, 100]
    "orange":  {"h": null, "s": null, "l": null},
    "yellow":  {"h": null, "s": null, "l": null},
    "green":   {"h": null, "s": null, "l": null},
    "aqua":    {"h": null, "s": null, "l": null},
    "blue":    {"h": null, "s": null, "l": null},
    "purple":  {"h": null, "s": null, "l": null},
    "magenta": {"h": null, "s": null, "l": null}
  },
  "localSuggestions": [
    {
      "maskType": "linear",
      "maskShape": {
        "startX": 0.5, // float [0.0, 1.0]
        "startY": 0.0, // float [0.0, 1.0]
        "endX": 0.5,   // float [0.0, 1.0]
        "endY": 0.4    // float [0.0, 1.0]
      },
      "params": {
        "exposure":    null, // or relative offset float [-5.0, 5.0]
        "contrast":    null, // or relative offset integer
        "highlights":  null, // or relative offset integer
        "shadows":     null, // or relative offset integer
        "whites":      null, // or relative offset integer
        "blacks":      null, // or relative offset integer
        "temperatureShift": null, // or relative offset integer [-3000, 3000]
        "tint":        null, // or relative offset integer
        "saturation":  null, // or relative offset integer
        "vibrance":    null  // or relative offset integer
      },
      "reason": "Rationale"
    },
    {
      "maskType": "radial",
      "maskShape": {
        "centerX": 0.5, 
        "centerY": 0.5, 
        "radiusX": 0.3, 
        "radiusY": 0.3, 
        "rotation": 0.0, 
        "feather": 0.5, 
        "inverted": false
      },
      "params": {
        "exposure": null,
        "shadows": null
      },
      "reason": "Rationale"
    }
  ]
}

YOUR JSON RESPONSE MUST START EXACTLY HERE:
{
''';
  }
}
