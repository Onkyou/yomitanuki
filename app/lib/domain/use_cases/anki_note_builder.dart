import 'dart:convert';

import '../models/anki_note.dart';
import '../models/anki_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/lookup_result.dart';

/// Turns a dictionary match plus the OCR line it came from into the note
/// AnkiMobile receives; the one place the field mapping lives (D5.5). Pure
/// logic over domain models, no I/O.
///
/// Word = headword, Reading = reading, Meaning = the senses' glosses joined
/// with `; `, one numbered line per sense when there are several, Example =
/// the OCR line, ExampleEN and Note empty (the URL builder omits empty
/// fields). Anki renders field text as HTML, so every value is HTML-escaped
/// first and line breaks are written as `<br>`.
class AnkiNoteBuilder {
  const AnkiNoteBuilder();

  /// Throws [ArgumentError] when [settings] has [AnkiSettings.problems]: a
  /// duplicate field name would silently drop a field, an empty deck or
  /// note type would make AnkiMobile refuse the add (D5.8).
  AnkiNote build({
    required LookupResult lookup,
    required String contextLine,
    required AnkiSettings settings,
  }) {
    final problems = settings.problems;
    if (problems.isNotEmpty) {
      throw ArgumentError.value(settings, 'settings', problems.join(' '));
    }
    final entry = lookup.entry;
    String name(AnkiField field) => settings.fieldName(field).trim();
    return AnkiNote(
      deck: settings.deck.trim(),
      noteType: settings.noteType.trim(),
      fields: {
        name(AnkiField.word): html(entry.headword),
        name(AnkiField.reading): html(entry.reading),
        name(AnkiField.meaning): meaning(entry.senses),
        name(AnkiField.example): html(contextLine),
        name(AnkiField.exampleEn): '',
        name(AnkiField.note): '',
      },
    );
  }

  /// `to eat` for one sense; `1. to eat<br>2. to live on; to live off` for
  /// several. Glosses are escaped before the markup is added.
  static String meaning(List<Sense> senses) {
    final lines = senses.map((s) => html(s.glosses.join('; '))).toList();
    if (lines.length == 1) return lines.single;
    return [for (final (i, line) in lines.indexed) '${i + 1}. $line']
        .join('<br>');
  }

  static const _escape = HtmlEscape(HtmlEscapeMode.element);

  /// [text] as HTML element content: `&`, `<`, `>` escaped, newlines as
  /// `<br>`.
  static String html(String text) =>
      _escape.convert(text).replaceAll('\n', '<br>');
}
