import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clone_stamp/clone_stamp_state.dart';
import '../healing/healing_state.dart';
import '../spot_heal/spot_heal_state.dart';
import '../dodge_burn/dodge_burn_state.dart';
import '../sponge/sponge_state.dart';

/// Deactivate a brush when the user navigates to another tool.
///
/// Each brush has a different state shape — dispatches by manifest [id].
/// Lives separately from [brush_manifest.dart] to avoid a circular import.
void deactivateBrush(String brushId, WidgetRef ref) {
  switch (brushId) {
    case 'spot_removal':
      ref
          .read(spotRemoveStateProvider.notifier)
          .setMode(SpotRemoveMode.inactive);
    case 'healing':
      ref.read(healingStateProvider.notifier).setMode(HealingMode.inactive);
    case 'spot_heal':
      ref.read(spotHealStateProvider.notifier).setMode(SpotHealMode.inactive);
    case 'dodge_burn':
      ref
          .read(dodgeBurnStateProvider.notifier)
          .setBrushMode(DodgeBurnBrushMode.inactive);
    case 'sponge':
      ref
          .read(spongeStateProvider.notifier)
          .setBrushMode(SpongeBrushMode.inactive);
  }
}
