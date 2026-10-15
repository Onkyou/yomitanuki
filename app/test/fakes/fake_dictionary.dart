import 'dart:async';

import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/ports/dictionary.dart';

/// An in-memory [Dictionary] for tests. Two modes:
///
/// * injected: [onLookup] or [results] answers every lookup (WP4's view and
///   view-model tests);
/// * default (neither given): exact headword/reading prefix matches over
///   [entries] plus the canned inflected surfaces in [inflected]
///   (食べた → 食べる [past]), longest surface first, no real deinflection.
///
/// Records every lookup as `(text, index)`; [manual] parks each call on a
/// completer in [pending] so answers can arrive out of order.
class FakeDictionary implements Dictionary {
  FakeDictionary({
    this.results,
    Map<String, KanjiEntry>? kanjiEntries,
    List<DictionaryEntry>? entries,
    this.onLookup,
    this.error,
  }) : kanjiEntries = kanjiEntries ?? defaultKanji,
       entries = entries ?? defaultEntries;

  List<LookupResult>? results;
  Map<String, KanjiEntry> kanjiEntries;
  final List<DictionaryEntry> entries;
  List<LookupResult> Function(String text, int index)? onLookup;
  Object? error;

  final List<(String, int)> lookups = [];
  final List<String> kanjiLookups = [];

  /// When true, every [lookupAt] call parks on its own completer in
  /// [pending] (in call order) until the test completes it.
  bool manual = false;
  final List<Completer<void>> pending = [];

  /// Canned inflected surfaces: (surface, base form, reasons, entry id).
  static const List<(String, String, List<String>, int)> inflected = [
    ('食べた', '食べる', ['past'], 1358280),
  ];

  static const List<DictionaryEntry> defaultEntries = [
    DictionaryEntry(
      id: 1358280,
      headword: '食べる',
      reading: 'たべる',
      senses: [
        Sense(glosses: ['to eat'], partsOfSpeech: ['v1', 'vt']),
      ],
      isCommon: true,
    ),
    DictionaryEntry(
      id: 1522150,
      headword: '本',
      reading: 'ほん',
      senses: [
        Sense(glosses: ['book', 'volume'], partsOfSpeech: ['n']),
      ],
      isCommon: true,
    ),
    DictionaryEntry(
      id: 1524060,
      headword: '魔王',
      reading: 'まおう',
      senses: [
        Sense(glosses: ['devil king', 'demon lord'], partsOfSpeech: ['n']),
      ],
      isCommon: false,
    ),
  ];

  static const Map<String, KanjiEntry> defaultKanji = {
    '食': KanjiEntry(
      literal: '食',
      meanings: ['eat', 'food'],
      onReadings: ['ショク', 'ジキ'],
      kunReadings: ['く.う', 'た.べる'],
      strokeCount: 9,
      grade: 2,
      jlpt: 4,
    ),
  };

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
    if (f != null) {
      return f(text, index);
    }
    final r = results;
    if (r != null) {
      return List.of(r);
    }
    return _prefixMatches(text, index);
  }

  List<LookupResult> _prefixMatches(String text, int index) {
    final rest = text.substring(index);
    final matches = [
      for (final entry in entries)
        for (final form in {entry.headword, entry.reading})
          if (rest.startsWith(form))
            LookupResult(
              start: index,
              length: form.length,
              surface: form,
              baseForm: form,
              matchedReading: form == entry.headword ? entry.reading : form,
              reasons: const [],
              entry: entry,
              matchedSenseIndexes: const [],
            ),
    ];
    for (final (surface, base, reasons, id) in inflected) {
      if (rest.startsWith(surface)) {
        matches.add(
          LookupResult(
            start: index,
            length: surface.length,
            surface: surface,
            baseForm: base,
            matchedReading: entries.firstWhere((e) => e.id == id).reading,
            reasons: reasons,
            entry: entries.firstWhere((e) => e.id == id),
            matchedSenseIndexes: const [],
          ),
        );
      }
    }
    matches.sort((a, b) => b.length - a.length);
    return matches;
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
  matchedReading: 'たべる',
  reasons: ['past', 'negative', 'potential'],
  entry: taberuEntry,
  matchedSenseIndexes: [],
);
