/// One JMdict entry, English glosses only (D7).
class DictionaryEntry {
  const DictionaryEntry({
    required this.id,
    required this.headword,
    required this.reading,
    required this.senses,
    required this.isCommon,
  });

  /// JMdict `ent_seq`.
  final int id;

  /// The primary kanji form, or the kana form when the entry has no kanji.
  final String headword;

  /// The primary kana reading.
  final String reading;
  final List<Sense> senses;
  final bool isCommon;
}

class Sense {
  const Sense({required this.glosses, required this.partsOfSpeech});

  final List<String> glosses;

  /// JMdict part-of-speech tags, e.g. `v1`, `adj-i`, `n`.
  final List<String> partsOfSpeech;
}

/// One KANJIDIC2 character.
class KanjiEntry {
  const KanjiEntry({
    required this.literal,
    required this.meanings,
    required this.onReadings,
    required this.kunReadings,
    this.strokeCount,
    this.grade,
    this.jlpt,
  });

  final String literal;
  final List<String> meanings;
  final List<String> onReadings;
  final List<String> kunReadings;
  final int? strokeCount;
  final int? grade;
  final int? jlpt;
}
