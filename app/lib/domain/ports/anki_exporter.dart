import '../models/anki_note.dart';

/// Hands a note to AnkiMobile via its URL scheme (WP5).
abstract interface class AnkiExporter {
  Future<AnkiExportOutcome> add(AnkiNote note);
}
