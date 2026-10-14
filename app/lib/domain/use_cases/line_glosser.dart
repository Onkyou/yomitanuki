import '../models/line_gloss.dart';
import '../models/lookup_result.dart';
import '../ports/dictionary.dart';
import '../text/lookup_breaks.dart';
import 'furigana.dart';

/// Cuts an OCR line into the words the dictionary recognises, left to right
/// (WP6b). At each offset the first `Dictionary.lookupAt` result is taken:
/// the port already puts the longest surface, then the best-ranked entry,
/// first (D3.5). Text that matches nothing, and break characters (spaces,
/// punctuation), are plain spans; neighbouring plain text is one span.
///
/// Tapping a character still starts its own lookup at that character (C15),
/// so a wrong cut costs the reader nothing but a misplaced underline.
class LineGlosser {
  const LineGlosser(this._dictionary);

  final Dictionary _dictionary;

  /// A dictionary error propagates; the caller decides what a line without
  /// a gloss looks like.
  Future<LineGloss> gloss(String line) async {
    final spans = <GlossSpan>[];
    var plainFrom = -1;

    void endPlain(int at) {
      if (plainFrom < 0) return;
      final surface = line.substring(plainFrom, at);
      spans.add(
        GlossSpan(
          start: plainFrom,
          length: surface.length,
          surface: surface,
          ruby: [RubySegment(surface)],
        ),
      );
      plainFrom = -1;
    }

    var i = 0;
    while (i < line.length) {
      final step = _codePointLength(line, i);
      final match = lookupBreaks.contains(line.codeUnitAt(i))
          ? null
          : await _best(line, i);
      if (match == null) {
        if (plainFrom < 0) plainFrom = i;
        i += step;
        continue;
      }
      endPlain(i);
      spans.add(_span(match, i));
      i += match.length;
    }
    endPlain(line.length);
    return LineGloss(line, spans);
  }

  /// The first result at [i], unless it is not the text at [i]: the spans must
  /// concatenate to the line whatever the adapter returns. Null then, and
  /// when nothing matched or the match consumes no text.
  Future<LookupResult?> _best(String line, int i) async {
    final results = await _dictionary.lookupAt(line, i);
    if (results.isEmpty) {
      return null;
    }
    final r = results.first;
    return r.length > 0 && r.start == i && line.startsWith(r.surface, i)
        ? r
        : null;
  }

  GlossSpan _span(LookupResult r, int start) => GlossSpan(
    start: start,
    length: r.length,
    surface: r.surface,
    reading: r.matchedReading,
    gloss: r.entry.senses.isEmpty
        ? ''
        : r.entry.senses.first.glosses.join(', '),
    baseForm: r.baseForm,
    ruby: furigana(r.surface, r.baseForm, r.matchedReading),
  );

  static int _codePointLength(String text, int i) {
    final unit = text.codeUnitAt(i);
    final isHigh = unit & 0xFC00 == 0xD800;
    return isHigh &&
            i + 1 < text.length &&
            text.codeUnitAt(i + 1) & 0xFC00 == 0xDC00
        ? 2
        : 1;
  }
}
