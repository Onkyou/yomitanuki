import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../domain/ports/wake_lock.dart';

/// [WakeLock] on `wakelock_plus`: on iOS it sets `isIdleTimerDisabled`, which
/// stops the auto-lock timer while it is held. Exercised on the device only;
/// the plugin has no host-side implementation worth faking.
class WakelockPlusWakeLock implements WakeLock {
  @override
  Future<void> setEnabled(bool enabled) =>
      enabled ? WakelockPlus.enable() : WakelockPlus.disable();
}
