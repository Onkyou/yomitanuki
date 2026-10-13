import 'dart:io';

/// Wall-clock samples per label, reported as medians when `ORT_TIMING` is
/// set (`ORT_TIMING=1 flutter test ...`); silent otherwise, so the gate's
/// output stays about pass/fail. Mac numbers are relative (WP0 C9); the
/// phone is measured in WP2 task 1.
class Timing {
  final Map<String, List<Duration>> _samples = {};

  static bool get enabled =>
      (Platform.environment['ORT_TIMING'] ?? '').isNotEmpty;

  /// Repeats [body] `ORT_TIMING` times (default 1 when unset) and returns
  /// the last result; every run is sampled under [label].
  Future<T> measure<T>(String label, Future<T> Function() body) async {
    final repeats = enabled
        ? int.tryParse(Platform.environment['ORT_TIMING']!) ?? 1
        : 1;
    late T result;
    for (var i = 0; i < repeats; i++) {
      final clock = Stopwatch()..start();
      result = await body();
      _samples.putIfAbsent(label, () => []).add(clock.elapsed);
    }
    return result;
  }

  void report(String what) {
    if (!enabled) return;
    final out = StringBuffer('timing [$what], median of n per label:\n');
    for (final MapEntry(key: label, value: samples) in _samples.entries) {
      final sorted = samples.map((d) => d.inMicroseconds).toList()..sort();
      final median = sorted[sorted.length ~/ 2] / 1000;
      out.writeln(
        '  ${label.padRight(40)} ${median.toStringAsFixed(1).padLeft(8)} ms '
        '(n=${sorted.length}, min ${(sorted.first / 1000).toStringAsFixed(1)})',
      );
    }
    stderr.write(out);
  }
}
