import '../models/anki_note.dart';
import '../models/anki_settings.dart';
import '../models/dictionary_entry.dart';
import '../models/line_gloss.dart';
import '../models/lookup_result.dart';
import '../text/html.dart';

/// Turns a dictionary match plus the OCR line it came from into the note
/// AnkiMobile receives; the one place the field mapping lives (D5.5, shape
/// changed by WP6d). Pure logic over domain models, no I/O.
///
/// Word = the base form the reader saw (D6d.1), Reading = the matched
/// reading, Meaning = at most [maxSenses] senses, the ones that fit the
/// inflection first (D6d.2), Example = the OCR line with the target in bold
/// and the other words in ruby when the line has been glossed (D6d.3),
/// ExampleEN = its English translation when there is one (D6c.4), Note
/// empty (the URL builder omits empty fields). Anki renders field text as
/// HTML, so every value is HTML-escaped first and line breaks are written
/// as `<br>`.
class AnkiNoteBuilder {
  const AnkiNoteBuilder();

  /// Most senses a word note lists: a recall answer, not a dictionary page.
  static const maxSenses = 3;

  /// On every note, so the cards this app made can be found and bulk-edited
  /// (D6d.5).
  static const _tag = 'yomitanuki';

  /// Throws [ArgumentError] when [settings] has [AnkiSettings.problems]: a
  /// duplicate field name would silently drop a field, an empty deck or
  /// note type would make AnkiMobile refuse the add (D5.8). [gloss] is the
  /// glossed [contextLine]; without it the example has no readings.
  AnkiNote build({
    required LookupResult lookup,
    required String contextLine,
    required AnkiSettings settings,
    String? contextTranslation,
    LineGloss? gloss,
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
        name(AnkiField.word): escapeHtml(lookup.baseForm),
        name(AnkiField.reading): escapeHtml(lookup.matchedReading),
        name(AnkiField.meaning): meaning(_senses(lookup)),
        name(AnkiField.example): gloss == null
            ? _markTarget(contextLine, lookup)
            : gloss.rubyHtml(
                exceptStart: lookup.start,
                exceptLength: lookup.length,
              ),
        name(AnkiField.exampleEn): escapeHtml(contextTranslation ?? ''),
        name(AnkiField.note): '',
      },
      tags: const [_tag],
    );
  }

  /// At most [maxSenses] senses: the matched ones first, then the others, each
  /// group in dictionary order.
  static List<Sense> _senses(LookupResult lookup) {
    final senses = lookup.entry.senses;
    final matched = [
      for (final i in lookup.matchedSenseIndexes)
        if (i >= 0 && i < senses.length) i,
    ];
    final rest = [
      for (var i = 0; i < senses.length; i++)
        if (!matched.contains(i)) i,
    ];
    return [
      for (final i in [...matched, ...rest].take(maxSenses)) senses[i],
    ];
  }

  /// [line] escaped with the looked-up text in `<b>`; plain when the match
  /// does not lie inside the line.
  static String _markTarget(String line, LookupResult lookup) {
    final start = lookup.start;
    final end = start + lookup.length;
    if (start < 0 || lookup.length <= 0 || end > line.length) {
      return escapeHtml(line);
    }
    return '${escapeHtml(line.substring(0, start))}'
        '<b>${escapeHtml(line.substring(start, end))}</b>'
        '${escapeHtml(line.substring(end))}';
  }

  /// A note for a whole OCR line, a Japanese to English recognition card
  /// (D6b.3, shape changed by D6d.4): Word = the plain line, Reading = the
  /// line with furigana, Meaning = the translation as the answer followed by
  /// the recognised words' glosses in a `<details>` crib, every other field
  /// empty (Note stays the reader's, D6d.6). Goes to [AnkiSettings.sentenceNoteType]
  /// when set, tagged `yomitanuki` and `sentence`. Throws like [build].
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
    final sentenceType = settings.sentenceNoteType?.trim() ?? '';
    return AnkiNote(
      deck: settings.deck.trim(),
      noteType: sentenceType.isEmpty ? settings.noteType.trim() : sentenceType,
      fields: {
        name(AnkiField.word): escapeHtml(gloss.line),
        name(AnkiField.reading): gloss.rubyHtml(),
        name(AnkiField.meaning): _sentenceMeaning(gloss, contextTranslation),
        name(AnkiField.example): '',
        name(AnkiField.exampleEn): '',
        name(AnkiField.note): '',
      },
      tags: const [_tag, _sentenceTag],
    );
  }

  /// Added to sentence notes next to `yomitanuki` (D6d.5).
  static const _sentenceTag = 'sentence';

  static String _sentenceMeaning(LineGloss gloss, String? translation) {
    final answer = escapeHtml(translation ?? '');
    if (!gloss.hasMatches) return answer;
    final crib =
        '<details><summary>Words</summary>'
        '${escapeHtml(gloss.glossLine)}</details>';
    return answer.isEmpty ? crib : '$answer<br>$crib';
  }

  /// `to eat` for one sense; `1. to eat<br>2. to live on; to live off` for
  /// several. Glosses are escaped before the markup is added.
  static String meaning(List<Sense> senses) {
    final lines = senses.map((s) => escapeHtml(s.glosses.join('; '))).toList();
    if (lines.length == 1) return lines.single;
    return [for (final (i, line) in lines.indexed) '${i + 1}. $line']
        .join('<br>');
  }
}
