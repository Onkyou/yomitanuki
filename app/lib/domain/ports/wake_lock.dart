/// Keeps the screen from auto-locking while the reader is in use (D6f.6).
/// Implemented by the `wakelock_plus` adapter and by a fake in every other
/// test.
abstract interface class WakeLock {
  /// Holds ([enabled]) or releases the lock. Idempotent: asking for the state
  /// that already holds changes nothing.
  Future<void> setEnabled(bool enabled);
}
