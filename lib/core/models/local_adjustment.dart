import 'package:flutter/foundation.dart';

import 'local_params.dart';
import 'mask_shape.dart';

@immutable
class LocalAdjustment {
  final String id;
  final String name;
  final MaskShape mask;
  final LocalParams params;
  final bool enabled;

  const LocalAdjustment({
    required this.id,
    required this.name,
    required this.mask,
    this.params = LocalParams.neutral,
    this.enabled = true,
  });

  LocalAdjustment copyWith({
    String? name,
    MaskShape? mask,
    LocalParams? params,
    bool? enabled,
  }) =>
      LocalAdjustment(
        id: id,
        name: name ?? this.name,
        mask: mask ?? this.mask,
        params: params ?? this.params,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mask': mask.toJson(),
        'params': params.toJson(),
        'enabled': enabled,
      };

  factory LocalAdjustment.fromJson(Map<String, dynamic> j) => LocalAdjustment(
        id: j['id'] as String,
        name: j['name'] as String,
        mask: MaskShape.fromJson(j['mask'] as Map<String, dynamic>),
        params: LocalParams.fromJson(j['params'] as Map<String, dynamic>),
        enabled: j['enabled'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAdjustment &&
          id == other.id &&
          name == other.name &&
          mask == other.mask &&
          params == other.params &&
          enabled == other.enabled);

  @override
  int get hashCode => Object.hash(id, name, mask, params, enabled);
}