/// The slots of a vocabulary note, in the order the settings screen shows
/// them. Each maps to a field name of the user's own note type via
/// [AnkiSettings.fieldName].
enum AnkiField {
  word('Word'),
  reading('Reading'),
  meaning('Meaning'),
  example('Example'),
  exampleEn('Example (English)'),
  note('Note');

  const AnkiField(this.label);

  /// How the slot is named to the user (not the Anki field name).
  final String label;
}

/// Where notes go: deck, note type and the note type's field names (WP5).
/// Immutable; defaults are the Frieren deck from PLAN.md section 1.
class AnkiSettings {
  const AnkiSettings({
    required this.deck,
    required this.noteType,
    required this.fieldNames,
    this.sentenceNoteType,
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

  /// The note type of sentence notes (D6d); null or blank means the same as
  /// [noteType]. Its fields are the same six names. A separate type keeps
  /// sentences out of the word notes' duplicate check.
  final String? sentenceNoteType;

  /// May be partial: a slot without an entry resolves to its default name.
  final Map<AnkiField, String> fieldNames;

  String fieldName(AnkiField field) =>
      fieldNames[field] ?? defaults.fieldNames[field]!;

  /// What makes these settings unusable for building a note, as sentences
  /// for the user; empty when they are usable. Values are judged trimmed:
  /// surrounding whitespace is tolerated here and dropped when a note is
  /// built. Shared by the settings screen (shown as it is typed) and
  /// [AnkiNoteBuilder], which refuses to build on any problem (D5.8).
  List<String> get problems {
    final out = <String>[];
    if (deck.trim().isEmpty) out.add('Deck must not be empty.');
    if (noteType.trim().isEmpty) out.add('Note type must not be empty.');
    final seen = <String>{};
    for (final field in AnkiField.values) {
      final name = fieldName(field).trim();
      if (name.isEmpty) {
        out.add('The field name for ${field.label} must not be empty.');
      } else if (!seen.add(name)) {
        out.add('The field name "$name" is used twice.');
      }
    }
    return out;
  }

  AnkiSettings copyWith({
    String? deck,
    String? noteType,
    String? sentenceNoteType,
  }) => AnkiSettings(
    deck: deck ?? this.deck,
    noteType: noteType ?? this.noteType,
    fieldNames: fieldNames,
    sentenceNoteType: sentenceNoteType ?? this.sentenceNoteType,
  );

  AnkiSettings withFieldName(AnkiField field, String name) => AnkiSettings(
    deck: deck,
    noteType: noteType,
    fieldNames: Map.unmodifiable({...fieldNames, field: name}),
    sentenceNoteType: sentenceNoteType,
  );

  @override
  bool operator ==(Object other) =>
      other is AnkiSettings &&
      other.deck == deck &&
      other.noteType == noteType &&
      other.sentenceNoteType == sentenceNoteType &&
      AnkiField.values.every((f) => other.fieldName(f) == fieldName(f));

  @override
  int get hashCode => Object.hash(
    deck,
    noteType,
    sentenceNoteType,
    Object.hashAll(AnkiField.values.map(fieldName)),
  );

  @override
  String toString() =>
      'AnkiSettings($deck, $noteType, sentences: $sentenceNoteType, '
      '${AnkiField.values.map((f) => '${f.name}: ${fieldName(f)}').join(', ')})';
}
