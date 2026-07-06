import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/crop_params.dart';
import '../providers.dart';

/// 是否处于"裁剪编辑"模式
class CropEditModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final cropEditModeProvider = NotifierProvider<CropEditModeNotifier, bool>(
  CropEditModeNotifier.new,
);

/// 编辑期间的草稿，进入模式时由 develop_screen 用当前 crop 初始化；
/// 提交时写回 currentParams.crop；取消时直接丢弃
class CropDraftNotifier extends Notifier<CropParams> {
  @override
  CropParams build() => CropParams.identity;

  void reset(CropParams initial) => state = initial;
  void update(CropParams next) => state = next;
}

final cropDraftProvider = NotifierProvider<CropDraftNotifier, CropParams>(
  CropDraftNotifier.new,
);

/// 进入裁剪模式：把 currentParams.crop 拷贝到 draft，flag 翻成 true
void enterCropMode(WidgetRef ref) {
  final cur = ref.read(currentParamsNotifierProvider);
  ref.read(cropDraftProvider.notifier).reset(cur.crop);
  ref.read(cropEditModeProvider.notifier).set(true);
}

/// 提交：把 draft 写回 currentParams.crop（触发撤销栈），关闭模式
void commitCrop(WidgetRef ref) {
  final draft = ref.read(cropDraftProvider);
  final cur = ref.read(currentParamsNotifierProvider);
  if (cur.crop != draft) {
    ref
        .read(currentParamsNotifierProvider.notifier)
        .update(cur.copyWith(crop: draft));
  }
  ref.read(cropEditModeProvider.notifier).set(false);
}

/// 取消：直接关闭模式
void cancelCrop(WidgetRef ref) {
  ref.read(cropEditModeProvider.notifier).set(false);
}
