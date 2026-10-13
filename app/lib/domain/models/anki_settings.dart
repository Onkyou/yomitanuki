/// The slots of a vocabulary note, in the order the settings screen shows
/// them. Each maps to a field name of the user's own note type via
/// [AnkiSettings.fieldName].
enum AnkiField { word, reading, meaning, example, exampleEn, note }

/// Where notes go: deck, note type and the note type's field names (WP5).
/// Immutable; defaults are the Frieren deck from PLAN.md section 1.
class AnkiSettings {
  const AnkiSettings({
    required this.deck,
    required this.noteType,
    required this.fieldNames,
  });

  static const defaults = AnkiSettings(
    deck: 'Japanese::Frieren Vol. 1',
    noteType: 'Frieren Vocab (JP→EN)',
    fieldNames: {
      AnkiField.word: 'Word',
      AnkiField.reading: 'Reading',
      AnkiField.meaning: 'Meaning',
      AnkiField.example: 'Example',
      AnkiField.exampleEn: 'ExampleEN',
      AnkiField.note: 'Note',
    },
  );

  /// Deck name; nested decks separated by `::` as Anki writes them.
  final String deck;

  final String noteType;

  /// May be partial: a slot without an entry resolves to its default name.
  final Map<AnkiField, String> fieldNames;

  String fieldName(AnkiField field) =>
      fieldNames[field] ?? defaults.fieldNames[field]!;

  AnkiSettings copyWith({String? deck, String? noteType}) => AnkiSettings(
    deck: deck ?? this.deck,
    noteType: noteType ?? this.noteType,
    fieldNames: fieldNames,
  );

  AnkiSettings withFieldName(AnkiField field, String name) => AnkiSettings(
    deck: deck,
    noteType: noteType,
    fieldNames: Map.unmodifiable({...fieldNames, field: name}),
  );

  @override
  bool operator ==(Object other) =>
      other is AnkiSettings &&
      other.deck == deck &&
      other.noteType == noteType &&
      AnkiField.values.every((f) => other.fieldName(f) == fieldName(f));

  @override
  int get hashCode => Object.hash(
    deck,
    noteType,
    Object.hashAll(AnkiField.values.map(fieldName)),
  );

  @override
  String toString() =>
      'AnkiSettings($deck, $noteType, '
      '${AnkiField.values.map((f) => '${f.name}: ${fieldName(f)}').join(', ')})';
}
