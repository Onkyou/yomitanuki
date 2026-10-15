import '../text/html.dart';

/// A stretch of a [GlossSpan]'s surface and the small kana written over it
/// (furigana); [ruby] is null for text that needs none (okurigana, kana).
class RubySegment {
  const RubySegment(this.text, [this.ruby]);

  final String text;
  final String? ruby;

  @override
  bool operator ==(Object other) =>
      other is RubySegment && other.text == text && other.ruby == ruby;

  @override
  int get hashCode => Object.hash(text, ruby);

  @override
  String toString() =>
      ruby == null ? 'RubySegment($text)' : 'RubySegment($text:$ruby)';
}

/// One stretch of an OCR line: a dictionary match (a word, possibly
/// inflected) or text the dictionary did not recognise. Offsets and lengths
/// are UTF-16 code units, like `LookupResult`.
class GlossSpan {
  const GlossSpan({
    required this.start,
    required this.length,
    required this.surface,
    required this.ruby,
    this.reading,
    this.gloss,
    this.baseForm,
    this.glossShort,
    this.extraSenses = 0,
    this.isFunctionWord = false,
  });

  final int start;
  final int length;
  final String surface;

  /// [surface] cut into segments, each with the reading to show over it.
  final List<RubySegment> ruby;

  /// `LookupResult.matchedReading`; null for an unmatched span.
  final String? reading;

  /// The first sense's glosses joined with `, `; null for an unmatched span.
  final String? gloss;

  /// `LookupResult.baseForm`; null for an unmatched span.
  final String? baseForm;

  /// The gloss for a one-line word row (D6e.2): the first gloss of up to two
  /// senses joined with ` · `, cut at a gloss boundary to about 32
  /// characters. Null for an unmatched span.
  final String? glossShort;

  /// Senses that apply to the match and are not in [glossShort]; 0 for an
  /// unmatched span.
  final int extraSenses;

  /// Every sense considered for [glossShort] is a particle, auxiliary,
  /// copula or conjunction: underlined, but not worth a row in the word list.
  final bool isFunctionWord;

  /// The dictionary recognised this span.
  bool get matched => reading != null;
}

/// An OCR line cut into [spans] that cover it end to end, in order. Plain
/// (unmatched) neighbours are one span.
class LineGloss {
  const LineGloss(this.line, this.spans);

  final String line;
  final List<GlossSpan> spans;

  /// The line with every matched word as its reading and everything else as
  /// written. A word's reading is its [GlossSpan.ruby] put together, not
  /// [GlossSpan.reading]: that is the base form's, and 食べた should read
  /// たべた, not たべる. Kana is not converted: ビール stays ビール.
  String get readingLine => spans.map(_readingOf).join();

  static String _readingOf(GlossSpan span) => span.matched
      ? span.ruby.map((s) => s.ruby ?? s.text).join()
      : span.surface;

  /// The line as HTML for an Anki field: every [RubySegment] with a reading
  /// is `<ruby>text<rt>reading</rt></ruby>`, the rest is text (D6d.4).
  ///
  /// A matched span that overlaps `[exceptStart, exceptStart + exceptLength)`
  /// is the word being tested: bold and without readings, so the reading is
  /// not given away when the field is on the front of a card (D6d.3). A plain
  /// stretch overlapping the range is bold only where it overlaps, because it
  /// is a merged run of unrecognised text, not the word. Everything is escaped
  /// before the markup is added.
  String rubyHtml({int? exceptStart, int? exceptLength}) {
    final from = exceptStart;
    // A zero or negative length is no target at all (a point inside a span
    // must not bold it or strip its ruby).
    final to = from == null || exceptLength == null || exceptLength <= 0
        ? null
        : from + exceptLength;
    return spans.map((s) => _spanHtml(s, from, to)).join();
  }

  static String _spanHtml(GlossSpan span, int? from, int? to) {
    final end = span.start + span.length;
    if (from == null || to == null || span.start >= to || end <= from) {
      return span.ruby.map(_segmentHtml).join();
    }
    if (span.matched) return '<b>${escapeHtml(span.surface)}</b>';
    final a = (from - span.start).clamp(0, span.surface.length);
    final b = (to - span.start).clamp(a, span.surface.length);
    return '${escapeHtml(span.surface.substring(0, a))}'
        '<b>${escapeHtml(span.surface.substring(a, b))}</b>'
        '${escapeHtml(span.surface.substring(b))}';
  }

  static String _segmentHtml(RubySegment segment) {
    final ruby = segment.ruby;
    final text = escapeHtml(segment.text);
    return ruby == null
        ? text
        : '<ruby>$text<rt>${escapeHtml(ruby)}</rt></ruby>';
  }

  /// The dictionary recognised at least one span; without one there is
  /// nothing to gloss and a sentence note would only repeat the line.
  bool get hasMatches => spans.any((s) => s.matched);

  /// `surface: gloss` for every matched span, one per line.
  String get glossLine => spans
      .where((s) => s.matched)
      .map((s) => '${s.surface}: ${s.gloss}')
      .join('\n');
}
