import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../brushes/brush_manifest.dart';
import '../utils/shader_pass_util.dart';

/// 构建所有 brush shader 的有序预热任务列表
///
/// [brushPrograms] 以 [BrushManifest.id] 为键，null 条目跳过
/// [composeProgram] 单独传入，因 compose 非画笔但仍需预热
List<(String, Future<void> Function())> buildWarmupTasks({
  required Map<String, ui.FragmentProgram?> brushPrograms,
  required ui.FragmentProgram? composeProgram,
  required ui.Image developOutput,
  required int targetWidth,
  required int targetHeight,
}) {
  final tasks = <(String, Future<void> Function())>[];

  for (final m in brushManifests) {
    final prog = brushPrograms[m.id];
    if (prog != null) {
      final layer = m.layerFactory(prog);
      tasks.add((
        m.id,
        () => layer.warmup(developOutput, targetWidth, targetHeight),
      ));
    }
  }

  if (composeProgram != null) {
    tasks.add((
      'compose',
      () => _warmupComposeShader(
        composeProgram,
        developOutput,
        targetWidth,
        targetHeight,
      ),
    ));
  }

  return tasks;
}

/// 用 0 active layers 执行一次 compose shader，预编译 PSO（9 samplers）
Future<void> _warmupComposeShader(
  ui.FragmentProgram compose,
  ui.Image base,
  int tw,
  int th,
) async {
  final result = await runSingleShaderPass(
    shader: compose.fragmentShader(),
    outputWidth: tw,
    outputHeight: th,
    samplers: List.filled(9, base),
    setUniforms: (s) {
      s.setFloat(0, tw.toDouble());
      s.setFloat(1, th.toDouble());
      s.setFloat(2, 0.0); // uActiveLayerCount = 0
      for (int i = 3; i < 11; i++) {
        s.setFloat(i, 0.0);
      }
    },
  );
  result.dispose();
}

/// Session 级守卫——整个 app 生命周期内只预热一次
bool _warmupDone = false;
bool _warmupRunning = false;

/// 递归 addPostFrameCallback 链——每帧执行一个任务，与 UI 光栅化错开
/// [devClone] 在链完成或提前终止时由内部 dispose
void runWarmupChain(
  List<(String, Future<void> Function())> tasks,
  ui.Image devClone, {
  required bool Function() isMounted,
  void Function()? onComplete,
}) {
  if (_warmupDone || _warmupRunning) {
    devClone.dispose();
    onComplete?.call();
    return;
  }
  _warmupRunning = true;
  _step(tasks, 0, devClone, isMounted: isMounted, onComplete: onComplete);
}

void _step(
  List<(String, Future<void> Function())> tasks,
  int index,
  ui.Image devClone, {
  required bool Function() isMounted,
  void Function()? onComplete,
}) {
  if (!isMounted()) {
    devClone.dispose();
    _warmupRunning = false;
    onComplete?.call();
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!isMounted()) {
      devClone.dispose();
      _warmupRunning = false;
      onComplete?.call();
      return;
    }
    if (index >= tasks.length) {
      devClone.dispose();
      _warmupDone = true;
      _warmupRunning = false;
      onComplete?.call();
      return;
    }
    final (name, task) = tasks[index];
    try {
      debugPrint('[Warmup] $name (${index + 1}/${tasks.length})');
      await task();
    } catch (e) {
      debugPrint('[Warmup] $name failed: $e');
    }
    _step(
      tasks,
      index + 1,
      devClone,
      isMounted: isMounted,
      onComplete: onComplete,
    );
  });
}
