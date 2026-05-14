import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/adjustment_params.dart';

import '../services/ai/ai_color_service.dart';
import '../services/ai/ai_input_renderer.dart';
import '../services/ai/ai_settings.dart';
import 'image_state.dart';
import 'params_state.dart';
import 'render_state.dart';
import 'tether_state.dart';

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
  }) =>
      AIAutoState(
        enabled: enabled ?? this.enabled,
        inProgress: inProgress ?? this.inProgress,
        pendingSuggestion:
            clearPending ? null : (pendingSuggestion ?? this.pendingSuggestion),
        pendingShotPath:
            clearPending ? null : (pendingShotPath ?? this.pendingShotPath),
      );
}

class AIAutoNotifier extends Notifier<AIAutoState> {
  @override
  AIAutoState build() {
    AISettings.getAutoAI().then((v) {
      if (ref.mounted) state = state.copyWith(enabled: v);
    });

    ref.listen(activeShotProvider, (prev, next) {
      if (next == null) return;
      if (next.path == prev?.path) return;
      if (!state.enabled) return;
      scheduleAutoAI();
    });

    return const AIAutoState();
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await AISettings.setAutoAI(v);
  }

  Future<void> scheduleAutoAI() async {
    if (state.inProgress) return;

    final program = ref.read(shaderProgramProvider).value;
    final imageState = ref.read(imageNotifierProvider).value;
    if (program == null || imageState == null) return;

    final params = ref.read(currentParamsNotifierProvider);
    final lutState = ref.read(lutNotifierProvider);
    final shotPath = ref.read(activeFilePathProvider);

    state = state.copyWith(inProgress: true);

    String? tempPath;
    try {
      tempPath = await AIInputRenderer.renderToTempFile(
        program: program,
        sourceImage: imageState.uiImage,
        params: params,
        lutTexture: lutState.texture,
        lutSize: lutState.size,
        maxEdge: await AISettings.getMaxEdge(),
      );
      final bytes = await File(tempPath).readAsBytes();

      final result = await AIColorService.suggest(
        imageBytes: bytes,
        currentParams: params,
      );

      if (!ref.mounted) return;
      if (ref.read(activeFilePathProvider) != shotPath) return;

      state = state.copyWith(
        inProgress: false,
        pendingSuggestion: result,
        pendingShotPath: shotPath,
      );
    } catch (e) {
      debugPrint('Auto-AI failed: $e');
      if (ref.mounted) state = state.copyWith(inProgress: false);
    } finally {
      if (tempPath != null) {
        File(tempPath).delete().catchError((_) => File(tempPath!));
      }
    }
  }

  Future<void> requestNow() => scheduleAutoAI();

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

final aiAutoNotifierProvider =
    NotifierProvider<AIAutoNotifier, AIAutoState>(AIAutoNotifier.new);