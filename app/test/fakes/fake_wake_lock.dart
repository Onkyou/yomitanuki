import 'package:yomitanuki/domain/ports/wake_lock.dart';

/// A [WakeLock] that records what it was told. Every call yields before it
/// answers, like a real adapter does; [failure] is read when the call is made
/// and thrown after that yield. The yield is a microtask, not a timer: the
/// view model calls this from a sample, and a timer would be pending at the
/// end of every widget test that delivers a frame.
class FakeWakeLock implements WakeLock {
  /// Every argument [setEnabled] received, oldest first.
  final List<bool> history = [];

  /// Whether the lock is held now: the last value, off when never told.
  bool get enabled => history.isNotEmpty && history.last;

  /// When set, every call throws it.
  Exception? failure;

  @override
  Future<void> setEnabled(bool enabled) async {
    final f = failure;
    await Future<void>.value();
    if (f != null) throw f;
    history.add(enabled);
  }
}
