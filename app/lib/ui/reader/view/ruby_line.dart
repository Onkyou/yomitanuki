import 'package:flutter/material.dart';

import '../../../domain/models/line_gloss.dart';
import 'japanese_text.dart';

/// The OCR line as one ruby sentence: one tap target per code point, readings
/// over the kanji, an underline under every recognised word (two colours
/// alternating from word to word), wrapping as text does (D6e.1).
///
/// A cell is reported and keyed by its code point's UTF-16 start offset, so a
/// surrogate pair (𠮷, two units) is one cell and a tap on it never sends a
/// mid-character index. A lookup starts at the tapped character whatever the
/// cut (C15), so a wrong cut costs the reader a misplaced underline only.
///
/// Until [spans] arrive the cells are plain; there is no ruby row to reserve
/// then, so the line moves down a little when the gloss lands.
class RubyLine extends StatelessWidget {
  const RubyLine({
    required this.text,
    required this.spans,
    required this.highlight,
    required this.onTapCharacter,
    super.key,
  });

  /// Height of a cell (the tap target), without the ruby above it.
  static const double cellHeight = 52;

  /// Space between two words, so their underlines stay apart.
  static const double wordGap = 4;

  final String text;
  final List<GlossSpan>? spans;

  /// UTF-16 range `[from, to)` of the characters the lookup covers.
  final (int, int)? highlight;
  final void Function(int index) onTapCharacter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall?.japanese;
    final rubyStyle = theme.textTheme.labelMedium?.japanese.copyWith(
      height: 1.2,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final spans = this.spans;
    if (spans == null) {
      return Wrap(
        runSpacing: 8,
        children: [
          for (final (start, glyph) in _cells(text, 0))
            _cell(
              theme,
              style,
              start,
              glyph,
              highlighted: _marks(start, glyph),
            ),
        ],
      );
    }
    // Every cell reserves the ruby row when any word has readings, so plain
    // text and words share one baseline.
    final rubyHeight = spans.any((s) => s.matched && s.ruby.any(_hasRuby))
        ? (rubyStyle?.fontSize ?? 12) * 1.2
        : 0.0;
    var ordinal = 0;
    return Wrap(
      runSpacing: 8,
      children: [
        for (final span in spans)
          if (span.matched)
            _word(theme, style, rubyStyle, rubyHeight, span, ordinal++)
          else
            for (final (start, glyph) in _cells(span.surface, span.start))
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: rubyHeight),
                  _cell(
                    theme,
                    style,
                    start,
                    glyph,
                    highlighted: _marks(start, glyph),
                  ),
                ],
              ),
      ],
    );
  }

  static bool _hasRuby(RubySegment s) => s.ruby != null;

  bool _marks(int start, String glyph) {
    final (from, to) = highlight ?? (-1, -1);
    return start < to && start + glyph.length > from;
  }

  bool _marksAll(GlossSpan span) {
    final (from, to) = highlight ?? (-1, -1);
    return from <= span.start && to >= span.start + span.length;
  }

  Widget _word(
    ThemeData theme,
    TextStyle? style,
    TextStyle? rubyStyle,
    double rubyHeight,
    GlossSpan span,
    int ordinal,
  ) {
    final underline = ordinal.isEven
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    // One pill over the whole word when the lookup covers all of it.
    final whole = _marksAll(span);
    var offset = span.start;
    final segments = <Widget>[];
    for (final segment in span.ruby) {
      final ruby = segment.ruby;
      segments.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          // Start, not centre: a reading wider than its kanji must not push
          // the cells off the characters' own edge.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ruby != null)
              SizedBox(
                height: rubyHeight,
                child: Text(
                  ruby,
                  key: Key('ocr.ruby.$offset'),
                  style: rubyStyle,
                  maxLines: 1,
                ),
              )
            else
              SizedBox(height: rubyHeight),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (start, glyph) in _cells(segment.text, offset))
                  _cell(
                    theme,
                    style,
                    start,
                    glyph,
                    highlighted: !whole && _marks(start, glyph),
                  ),
              ],
            ),
          ],
        ),
      );
      offset += segment.text.length;
    }
    // A word wider than the line (a long inflected chain) shrinks to fit
    // rather than overflowing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.only(right: wordGap),
        child: DecoratedBox(
          decoration: whole ? _pill(theme) : const BoxDecoration(),
          child: DecoratedBox(
            key: Key('ocr.span.${span.start}'),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: underline, width: 2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: segments),
          ),
        ),
      ),
    );
  }

  BoxDecoration _pill(ThemeData theme) => BoxDecoration(
    color: theme.colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(6),
  );

  Widget _cell(
    ThemeData theme,
    TextStyle? style,
    int start,
    String glyph, {
    required bool highlighted,
  }) {
    return InkWell(
      key: Key('ocr.char.$start'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => onTapCharacter(start),
      // No `alignment` on the Container: that would make each cell fill the
      // row. Align with factors sizes to the glyph; the minimum height is the
      // tap target, its width is the glyph's.
      child: Container(
        constraints: const BoxConstraints(minHeight: cellHeight),
        decoration: highlighted ? _pill(theme) : null,
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(glyph, style: style),
        ),
      ),
    );
  }

  /// `(utf16 start, code point as a string)` for every code point of
  /// [text], whose first code unit sits at [base] in the OCR line.
  static Iterable<(int, String)> _cells(String text, int base) sync* {
    var offset = base;
    for (final rune in text.runes) {
      final glyph = String.fromCharCode(rune);
      yield (offset, glyph);
      offset += glyph.length;
    }
  }
}
