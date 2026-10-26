import 'dart:async';

/// Hand-driven time for the code under test: [create] is a `Timer` factory
/// and [now] the clock it runs on. Nothing fires until [advance] moves [now]
/// past a timer's deadline, so a test never waits for real time.
class FakeTimers {
  FakeTimers([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 13, 20);

  DateTime now;

  final _timers = <_FakeTimer>[];

  /// Timers that are scheduled and neither fired nor cancelled.
  int get pending => _timers.where((t) => !t.cancelled).length;

  Timer create(Duration duration, void Function() callback) {
    final timer = _FakeTimer(now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves [now] forward and fires every timer that came due, earliest first,
  /// including the ones a firing callback schedules inside the window.
  void advance(Duration duration) {
    now = now.add(duration);
    while (true) {
      final due =
          _timers
              .where((t) => !t.cancelled && !t.deadline.isAfter(now))
              .toList()
            ..sort((a, b) => a.deadline.compareTo(b.deadline));
      if (due.isEmpty) {
        return;
      }
      final next = due.first;
      _timers.remove(next);
      next.fired = true;
      next.callback();
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.deadline, this.callback);

  final DateTime deadline;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => 0;
}
