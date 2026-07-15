import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clone_stamp_model.dart';
import '../shared/stamp/stamp_mark.dart';
import '../../state/params/params_state.dart';

/// 污点修复交互模式
enum SpotRemoveMode {
  /// 非激活状态
  inactive,

  /// 激活状态：Alt+点击取样，点击/拖拽涂抹
  active,
}

@immutable
class SpotRemoveState {
  final SpotRemoveMode mode;

  /// 取样源点（归一化源图坐标 [0..1]），hold 键或按钮设置
  final ui.Offset? cloneSource;

  /// 涂抹半径（归一化，相对源图宽度）
  final double brushRadius;

  /// 边缘硬度 0..1，1=硬边，0=柔边
  final double brushHardness;

  /// 手机取样按钮开关（替代 hold 键）
  final bool samplingButtonOn;

  const SpotRemoveState({
    this.mode = SpotRemoveMode.inactive,
    this.cloneSource,
    this.brushRadius = 0.02,
    this.brushHardness = 1.0,
    this.samplingButtonOn = false,
  });

  SpotRemoveState copyWith({
    SpotRemoveMode? mode,
    ui.Offset? cloneSource,
    bool clearCloneSource = false,
    double? brushRadius,
    double? brushHardness,
    bool? samplingButtonOn,
  }) => SpotRemoveState(
    mode: mode ?? this.mode,
    cloneSource: clearCloneSource ? null : (cloneSource ?? this.cloneSource),
    brushRadius: brushRadius ?? this.brushRadius,
    brushHardness: brushHardness ?? this.brushHardness,
    samplingButtonOn: samplingButtonOn ?? this.samplingButtonOn,
  );
}

class SpotRemoveNotifier extends Notifier<SpotRemoveState> {
  @override
  SpotRemoveState build() => const SpotRemoveState();

  List<T> _marks<T extends StampMark>() =>
      ref
          .read(currentParamsNotifierProvider)
          .brushMarks['spot_removal']
          ?.cast<T>() ??
      const [];

  void _setMarks(List<StampMark> marks) {
    final params = ref.read(currentParamsNotifierProvider);
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(
          params.copyWith(
            brushMarks: {...params.brushMarks, 'spot_removal': marks},
          ),
        );
  }

  /// 切换模式
  void setMode(SpotRemoveMode mode) {
    state = state.copyWith(
      mode: mode,
      clearCloneSource: mode == SpotRemoveMode.inactive,
    );
  }

  /// 设置取样源点（Alt+点击 / 取样按钮点击）
  ///
  /// 设完源点后自动关闭取样按钮，与 Alt 松手行为一致
  /// 否则用取样按钮时第二次点击仍走 setCloneSource 而非 addSpot
  void setCloneSource(ui.Offset source) {
    state = state.copyWith(cloneSource: source, samplingButtonOn: false);
  }

  /// 清除取样源点
  void clearCloneSource() {
    state = state.copyWith(clearCloneSource: true);
  }

  /// 切换手机取样按钮
  void toggleSamplingButton() {
    state = state.copyWith(samplingButtonOn: !state.samplingButtonOn);
  }

  /// 设置涂抹半径
  void setBrushRadius(double radius) {
    state = state.copyWith(brushRadius: radius);
  }

  /// 设置边缘硬度
  void setBrushHardness(double hardness) {
    state = state.copyWith(brushHardness: hardness);
  }

  /// 添加一个新的 spot mark（从 cloneSource 复制到 target）
  void addSpot(ui.Offset target, {double? radiusOverride}) {
    final source = state.cloneSource;
    if (source == null) return;
    _addSpotRaw(source, target, radius: radiusOverride);
  }

  /// 添加 spot，指定自定义 source（拖拽涂抹时源点跟随目标同步移动）
  void addSpotWithSource(ui.Offset source, ui.Offset target) {
    _addSpotRaw(source, target);
  }

  void _addSpotRaw(ui.Offset source, ui.Offset target, {double? radius}) {
    final updated = <StampMark>[
      ..._marks<SpotMark>(),
      SpotMark(
        source: source,
        target: target,
        radius: radius ?? state.brushRadius,
        hardness: state.brushHardness,
        createdAt: DateTime.now(),
      ),
    ];
    _setMarks(updated);
  }

  /// 批量添加 spots（笔画结束时一次性提交，只触发一次管线重渲染）
  void addSpotsBatch(List<SpotMark> spots) {
    if (spots.isEmpty) return;
    final updated = <StampMark>[..._marks<SpotMark>(), ...spots];
    _setMarks(updated);
  }

  /// 删除指定 index 的 spot
  void removeSpot(int index) {
    if (index < 0 || index >= _marks<SpotMark>().length) return;
    final updated = <StampMark>[..._marks<SpotMark>()]..removeAt(index);
    _setMarks(updated);
  }

  /// 清空所有 spots
  void clearAll() {
    _setMarks(const []);
  }
}

final spotRemoveStateProvider =
    NotifierProvider<SpotRemoveNotifier, SpotRemoveState>(
      SpotRemoveNotifier.new,
    );
