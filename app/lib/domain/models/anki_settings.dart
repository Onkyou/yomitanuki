/// Where a note goes in AnkiMobile. The defaults match the existing deck
/// (PLAN.md section 1); WP5 adds persistence and a settings screen, the reader
/// only reads this value.
class AnkiSettings {
  const AnkiSettings({
    this.deck = 'Japanese::Frieren Vol. 1',
    this.noteType = 'Frieren Vocab (JP→EN)',
  });

  final String deck;
  final String noteType;

  @override
  bool operator ==(Object other) =>
      other is AnkiSettings && other.deck == deck && other.noteType == noteType;

  @override
  int get hashCode => Object.hash(deck, noteType);
}
