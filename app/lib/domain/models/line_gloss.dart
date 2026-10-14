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

  /// The dictionary recognised at least one span; without one there is
  /// nothing to gloss and a sentence note would only repeat the line.
  bool get hasMatches => spans.any((s) => s.matched);

  /// `surface: gloss` for every matched span, one per line.
  String get glossLine => spans
      .where((s) => s.matched)
      .map((s) => '${s.surface}: ${s.gloss}')
      .join('\n');
}
