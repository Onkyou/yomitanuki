import 'dart:convert';

import '../models/anki_note.dart';
import '../models/anki_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/line_gloss.dart';
import '../models/lookup_result.dart';

/// Turns a dictionary match plus the OCR line it came from into the note
/// AnkiMobile receives; the one place the field mapping lives (D5.5). Pure
/// logic over domain models, no I/O.
///
/// Word = headword (or the matched form when it is read differently),
/// Reading = the matched reading, Meaning = the senses' glosses joined
/// with `; `, one numbered line per sense when there are several, Example =
/// the OCR line, ExampleEN = its English translation when there is one
/// (D6c.4), Note empty (the URL builder omits empty fields). Anki renders field text as HTML, so every value is HTML-escaped
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
    String? contextTranslation,
  }) {
    final problems = settings.problems;
    if (problems.isNotEmpty) {
      throw ArgumentError.value(settings, 'settings', problems.join(' '));
    }
    final entry = lookup.entry;
    // A form read differently from the headword (ビール for 麦酒) is its own
    // word on the card; otherwise the headword, so 食べた files as 食べる.
    final word = lookup.matchedReading == entry.reading
        ? entry.headword
        : lookup.baseForm;
    String name(AnkiField field) => settings.fieldName(field).trim();
    return AnkiNote(
      deck: settings.deck.trim(),
      noteType: settings.noteType.trim(),
      fields: {
        name(AnkiField.word): html(word),
        name(AnkiField.reading): html(lookup.matchedReading),
        name(AnkiField.meaning): meaning(entry.senses),
        name(AnkiField.example): html(contextLine),
        name(AnkiField.exampleEn): html(contextTranslation ?? ''),
        name(AnkiField.note): '',
      },
    );
  }

  /// A note for a whole OCR line (D6b.3), same deck, note type and field
  /// names as a word note. Word and Example = the line, Reading = the line
  /// with its words read out, Meaning = one `surface: gloss` line per
  /// recognised word, ExampleEN = the line's translation when there is one
  /// (D6c.4), Note = `sentence` (the only thing that tells it from a word
  /// note). Throws like [build].
  AnkiNote buildSentence({
    required LineGloss gloss,
    required AnkiSettings settings,
    String? contextTranslation,
  }) {
    final problems = settings.problems;
    if (problems.isNotEmpty) {
      throw ArgumentError.value(settings, 'settings', problems.join(' '));
    }
    String name(AnkiField field) => settings.fieldName(field).trim();
    return AnkiNote(
      deck: settings.deck.trim(),
      noteType: settings.noteType.trim(),
      fields: {
        name(AnkiField.word): html(gloss.line),
        name(AnkiField.reading): html(gloss.readingLine),
        name(AnkiField.meaning): html(gloss.glossLine),
        name(AnkiField.example): html(gloss.line),
        name(AnkiField.exampleEn): html(contextTranslation ?? ''),
        name(AnkiField.note): sentenceTag,
      },
    );
  }

  /// What a sentence note carries in the Note field (D6b.3).
  static const sentenceTag = 'sentence';

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
