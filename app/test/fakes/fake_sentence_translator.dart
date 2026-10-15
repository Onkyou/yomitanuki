import 'dart:async';

import 'package:yomitanuki/domain/models/translation_status.dart';
import 'package:yomitanuki/domain/ports/sentence_translator.dart';

/// Answers [translations] (line to English, an unknown line comes back as
/// the empty string) and records every call. Reports [reported] as its
/// status.
///
/// [error] is thrown by [translate]; [statusError] by [status]. With
/// [manual] set, each [translate] call parks on its own completer in
/// [pending] (in call order) until the test completes it, so answers can
/// arrive after the reader moved on.
class FakeSentenceTranslator implements SentenceTranslator {
  FakeSentenceTranslator({
    this.reported = TranslationStatus.installed,
    Map<String, String>? translations,
    this.error,
    this.statusError,
  }) : translations = translations ?? {};

  TranslationStatus reported;
  final Map<String, String> translations;
  Object? error;
  Object? statusError;

  int statusCalls = 0;

  /// Every line [translate] received, oldest first.
  final List<String> lines = [];

  bool manual = false;
  final List<Completer<void>> pending = [];

  @override
  Future<TranslationStatus> status() async {
    statusCalls++;
    final e = statusError;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return reported;
  }

  @override
  Future<String> translate(String line) async {
    lines.add(line);
    if (manual) {
      final gate = Completer<void>();
      pending.add(gate);
      await gate.future;
    }
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return translations[line] ?? '';
  }
}
