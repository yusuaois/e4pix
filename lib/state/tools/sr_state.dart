import 'package:flutter_riverpod/legacy.dart';

/// 超分辨率预览开关（独立于 srEnabled）
final srPreviewEnabledProvider = StateProvider<bool>((ref) => false);
