/// One note to add to AnkiMobile. Field names are the note type's own.
class AnkiNote {
  const AnkiNote({
    required this.deck,
    required this.noteType,
    required this.fields,
    this.tags = const [],
  });

  final String deck;
  final String noteType;
  final Map<String, String> fields;
  final List<String> tags;
}

enum AnkiExportOutcome {
  /// AnkiMobile was opened with the note; it adds the note itself.
  handedOver,

  /// No app handles the `anki://` scheme on this device.
  ankiNotInstalled,
}
