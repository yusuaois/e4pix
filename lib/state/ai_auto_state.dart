import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/raw_formats.dart';
import '../services/ai/ai_color_service.dart';
import '../services/ai/ai_input_renderer.dart';
import '../services/ai/ai_settings.dart';
import 'providers.dart';

@immutable
class AIAutoState {
  final bool enabled;
  final bool inProgress;
  final AIColorSuggestion? pendingSuggestion;
  final String? pendingShotPath;

  const AIAutoState({
    this.enabled = false,
    this.inProgress = false,
    this.pendingSuggestion,
    this.pendingShotPath,
  });

  AIAutoState copyWith({
    bool? enabled,
    bool? inProgress,
    AIColorSuggestion? pendingSuggestion,
    String? pendingShotPath,
    bool clearPending = false,
  }) => AIAutoState(
    enabled: enabled ?? this.enabled,
    inProgress: inProgress ?? this.inProgress,
    pendingSuggestion: clearPending
        ? null
        : (pendingSuggestion ?? this.pendingSuggestion),
    pendingShotPath: clearPending
        ? null
        : (pendingShotPath ?? this.pendingShotPath),
  );
}

class AIAutoNotifier extends Notifier<AIAutoState> {
  Timer? _debounce;
  int _retryCount = 0;
  static const _maxRetries = 20;

  @override
  AIAutoState build() {
    AISettings.getAutoAI().then((v) {
      if (ref.mounted) state = state.copyWith(enabled: v);
    });
    ref.onDispose(() => _debounce?.cancel());
    return const AIAutoState();
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await AISettings.setAutoAI(v);
  }

  Future<void> onNewShotArrived(String shotPath) async {
    if (!state.enabled) return;

    final isRaw = RawFormats.isRaw(shotPath);
    final mode = ref.read(importModeProvider);

    if (mode == ImportMode.rawPriority && !isRaw) {
      debugPrint('[AI] skip JPG in rawPriority mode: $shotPath');
      return;
    }

    _debounce?.cancel();
    _retryCount = 0;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSuggestionForActive(shotPath);
    });
  }

  Future<void> _runSuggestionForActive(String triggerPath) async {
    if (!state.enabled || state.inProgress) return;

    if (ref.read(activeFilePathProvider) != triggerPath) {
      debugPrint('[AI] skip: activeFile changed');
      _retryCount = 0;
      return;
    }

    final imageState = ref.read(imageNotifierProvider).value;
    if (imageState == null ||
        imageState.isPreliminary ||
        imageState.path != triggerPath) {
      if (_retryCount >= _maxRetries) {
        debugPrint('[AI] give up after $_maxRetries retries (image not ready)');
        _retryCount = 0;
        return;
      }
      _retryCount++;
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 400),
        () => _runSuggestionForActive(triggerPath),
      );
      return;
    }

    _retryCount = 0;
    await _runSuggestion();
  }

  Future<void> requestNow() => _runSuggestion();

  Future<void> _runSuggestion() async {
    if (state.inProgress) return;

    final program = ref.read(shaderProgramProvider).value;
    final maskProgram = ref.read(maskShaderProgramProvider).value;
    final imageState = ref.read(imageNotifierProvider).value;
    if (program == null || maskProgram == null || imageState == null) return;

    final shotPath = ref.read(activeFilePathProvider);
    if (imageState.path != shotPath) return;
    if (imageState.isPreliminary) return;

    final params = ref.read(currentParamsNotifierProvider);
    final lutState = ref.read(lutNotifierProvider);

    state = state.copyWith(inProgress: true);

    String? tempPath;
    try {
      tempPath = await AIInputRenderer.renderToTempFile(
        program: program,
        maskProgram: maskProgram,
        sourceImage: imageState.uiImage,
        params: params,
        lutTexture: lutState.textureA,
        lutSize: lutState.sizeA,
        lutTextureB: lutState.textureB,
        lutSizeB: lutState.sizeB,
        curveTexture: ref.read(effectiveCurveTextureProvider),
        sharpenProgram: ref.read(sharpenShaderProgramProvider).value,
        maxEdge: await AISettings.getMaxEdge(),
      );
      final bytes = await File(tempPath).readAsBytes();

      final languageCode = Platform.localeName.split('_').first;
      final result = await AIColorService.suggest(
        imageBytes: bytes,
        currentParams: params,
        languageCode: languageCode,
      );

      if (!ref.mounted) return;
      if (ref.read(activeFilePathProvider) != shotPath) return;

      state = state.copyWith(
        pendingSuggestion: result,
        pendingShotPath: shotPath,
      );
    } catch (e) {
      debugPrint('Auto-AI failed: $e');
    } finally {
      if (ref.mounted) {
        state = state.copyWith(inProgress: false);
      }
      if (tempPath != null) {
        File(tempPath).delete().catchError((_) => File(tempPath!));
      }
    }
  }

  void dismissPending() {
    state = state.copyWith(clearPending: true);
  }

  void applyPending() {
    final s = state.pendingSuggestion;
    if (s == null) return;
    final cur = ref.read(currentParamsNotifierProvider);
    ref.read(currentParamsNotifierProvider.notifier).update(s.applyTo(cur));
    state = state.copyWith(clearPending: true);
  }
}

final aiAutoNotifierProvider = NotifierProvider<AIAutoNotifier, AIAutoState>(
  AIAutoNotifier.new,
);
