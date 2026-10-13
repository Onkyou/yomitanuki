import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/ports/dictionary.dart';

/// An in-memory [Dictionary] for widget tests: exact headword/reading
/// matches plus the canned inflected surfaces in [inflected] (食べた →
/// 食べる [past]), no real deinflection, longest surface first.
class FakeDictionary implements Dictionary {
  FakeDictionary({
    List<DictionaryEntry>? entries,
    Map<String, KanjiEntry>? kanji,
  }) : entries = entries ?? defaultEntries,
       kanjiEntries = kanji ?? defaultKanji;

  final List<DictionaryEntry> entries;
  final Map<String, KanjiEntry> kanjiEntries;

  /// Every (text, index) a test asked for, in order.
  final List<(String, int)> lookups = [];

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
    final rest = text.substring(index);
    final results = [
      for (final entry in entries)
        for (final form in {entry.headword, entry.reading})
          if (rest.startsWith(form))
            LookupResult(
              start: index,
              length: form.length,
              surface: form,
              baseForm: form,
              reasons: const [],
              entry: entry,
            ),
    ];
    for (final (surface, base, reasons, id) in inflected) {
      if (rest.startsWith(surface)) {
        results.add(
          LookupResult(
            start: index,
            length: surface.length,
            surface: surface,
            baseForm: base,
            reasons: reasons,
            entry: entries.firstWhere((e) => e.id == id),
          ),
        );
      }
    }
    results.sort((a, b) => b.length - a.length);
    return results;
  }

  @override
  Future<KanjiEntry?> kanji(String literal) async => kanjiEntries[literal];
}
