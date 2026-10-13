import 'dart:async';

import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/ports/dictionary.dart';

/// Answers [lookupAt] from [onLookup] (or [results] when unset) and [kanji]
/// from [kanjiEntries]. Records every lookup as `(text, index)`.
class FakeDictionary implements Dictionary {
  FakeDictionary({
    this.results = const [],
    this.kanjiEntries = const {},
    this.onLookup,
    this.error,
  });

  List<LookupResult> results;
  Map<String, KanjiEntry> kanjiEntries;
  List<LookupResult> Function(String text, int index)? onLookup;
  Object? error;

  final List<(String, int)> lookups = [];
  final List<String> kanjiLookups = [];

  /// When true, every [lookupAt] call parks on its own completer in
  /// [pending] (in call order) until the test completes it, so lookups can
  /// be answered out of order.
  bool manual = false;
  final List<Completer<void>> pending = [];

  @override
  Future<List<LookupResult>> lookupAt(String text, int index) async {
    lookups.add((text, index));
    if (manual) {
      final gate = Completer<void>();
      pending.add(gate);
      await gate.future;
    }
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    final f = onLookup;
    return f != null ? f(text, index) : List.of(results);
  }

  @override
  Future<KanjiEntry?> kanji(String literal) async {
    kanjiLookups.add(literal);
    return kanjiEntries[literal];
  }
}

/// A JMdict-shaped entry for 食べる, the running example in PLAN.md.
const taberuEntry = DictionaryEntry(
  id: 1358280,
  headword: '食べる',
  reading: 'たべる',
  senses: [
    Sense(glosses: ['to eat'], partsOfSpeech: ['v1', 'vt']),
    Sense(glosses: ['to live on (e.g. a salary)'], partsOfSpeech: ['v1', 'vt']),
  ],
  isCommon: true,
);

const shokuKanji = KanjiEntry(
  literal: '食',
  meanings: ['eat', 'food'],
  onReadings: ['ショク', 'ジキ'],
  kunReadings: ['く.う', 'た.べる'],
  strokeCount: 9,
  grade: 2,
  jlpt: 4,
);

/// 食べられなかった → 食べる, the deinflection example from PLAN.md WP3.
const taberareNakattaResult = LookupResult(
  start: 0,
  length: 8,
  surface: '食べられなかった',
  baseForm: '食べる',
  reasons: ['past', 'negative', 'potential'],
  entry: taberuEntry,
);
