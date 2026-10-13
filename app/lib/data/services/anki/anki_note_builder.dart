import '../../../domain/models/anki_note.dart';
import '../../../domain/models/anki_settings.dart';
import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';

/// Turns a dictionary match plus the OCR line it came from into the note
/// AnkiMobile receives; the one place the field mapping lives (D5.5).
///
/// Word = headword, Reading = reading, Meaning = the senses' glosses joined
/// with `; `, one numbered line per sense when there are several, Example =
/// the OCR line, ExampleEN and Note empty (the URL builder omits empty
/// fields). Anki renders field text as HTML, so lines are separated by
/// `<br>`.
class AnkiNoteBuilder {
  const AnkiNoteBuilder();

  AnkiNote build({
    required LookupResult lookup,
    required String contextLine,
    required AnkiSettings settings,
  }) {
    final entry = lookup.entry;
    return AnkiNote(
      deck: settings.deck,
      noteType: settings.noteType,
      fields: {
        settings.fieldName(AnkiField.word): entry.headword,
        settings.fieldName(AnkiField.reading): entry.reading,
        settings.fieldName(AnkiField.meaning): meaning(entry.senses),
        settings.fieldName(AnkiField.example): contextLine,
        settings.fieldName(AnkiField.exampleEn): '',
        settings.fieldName(AnkiField.note): '',
      },
    );
  }

  /// `to eat` for one sense; `1. to eat<br>2. to live on; to live off` for
  /// several.
  static String meaning(List<Sense> senses) {
    final lines = senses.map((s) => s.glosses.join('; ')).toList();
    if (lines.length == 1) return lines.single;
    return [for (final (i, line) in lines.indexed) '${i + 1}. $line']
        .join('<br>');
  }
}
