import '../models/dictionary_entry.dart';
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

  GlossSpan _span(LookupResult r, int start) {
    final senses = r.entry.senses;
    final matched = [
      for (final i in r.matchedSenseIndexes)
        if (i >= 0 && i < senses.length) i,
    ];
    // An empty list is an exact match; the first sense is the one the reader
    // most likely wants (D6e.2).
    final considered = [
      for (final i in matched.isEmpty && senses.isNotEmpty ? [0] : matched)
        senses[i],
    ];
    final (short, shown) = _shortGloss(considered);
    // An exact match leaves every sense applicable, so "+N" counts the rest
    // of the entry; a deinflected match counts only the senses it can be.
    final applicable = matched.isEmpty ? senses.length : matched.length;
    return GlossSpan(
      start: start,
      length: r.length,
      surface: r.surface,
      reading: r.matchedReading,
      gloss: senses.isEmpty ? '' : senses.first.glosses.join(', '),
      glossShort: short,
      extraSenses: applicable - shown,
      isFunctionWord:
          considered.isNotEmpty &&
          considered.every(
            (s) =>
                s.partsOfSpeech.isNotEmpty &&
                s.partsOfSpeech.every(_functionTags.contains),
          ),
      baseForm: r.baseForm,
      ruby: furigana(r.surface, r.baseForm, r.matchedReading),
    );
  }

  static const _functionTags = {
    'prt',
    'aux',
    'aux-v',
    'aux-adj',
    'cop',
    'cop-da',
  };

  static const _glossJoin = ' · ';
  static const _glossLimit = 32;

  /// The first gloss of each of the first two [senses], and how many made it
  /// in. Whole glosses drop from the end until the text fits; one gloss stays
  /// whole however long.
  static (String, int) _shortGloss(List<Sense> senses) {
    final glosses = [
      for (final s in senses.take(2))
        if (s.glosses.isNotEmpty) s.glosses.first,
    ];
    while (glosses.length > 1 &&
        glosses.join(_glossJoin).length > _glossLimit) {
      glosses.removeLast();
    }
    return (glosses.join(_glossJoin), glosses.length);
  }

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
