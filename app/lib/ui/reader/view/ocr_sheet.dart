import 'package:flutter/material.dart';

import '../../../domain/models/line_gloss.dart';
import '../../../domain/models/lookup_result.dart';
import '../view_model/reader_state.dart';
import 'bgra_image_view.dart';
import 'japanese_text.dart';
import 'lookup_results_view.dart';

/// The bottom panel that opens when a block is tapped: the OCR line with
/// every character its own tap target (C15: lookups start at the tapped
/// character), the lookup results under it. Vertical bubble text is shown
/// horizontally in v1.
class OcrSheet extends StatelessWidget {
  const OcrSheet({
    required this.ocrState,
    required this.lookupState,
    required this.onTapCharacter,
    required this.onAddToAnki,
    required this.onAddSentence,
    required this.onClose,
    super.key,
  });

  final OcrState ocrState;
  final LookupState lookupState;

  /// [index] is a UTF-16 offset into the OCR text, what `Dictionary.lookupAt`
  /// and `LookupResult.start` use.
  final void Function(int index) onTapCharacter;
  final void Function(LookupResult result) onAddToAnki;
  final VoidCallback onAddSentence;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return Material(
      key: const Key('ocr.sheet'),
      elevation: 8,
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  FilledButton.tonalIcon(
                    key: const Key('anki.addSentence'),
                    onPressed: _canAddSentence ? onAddSentence : null,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Add sentence'),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('ocr.close'),
                    tooltip: 'Back to the page',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    ?_cropThumbnail(),
                    _ocrLine(theme),
                    const SizedBox(height: 8),
                    LookupResultsView(
                      state: lookupState,
                      onAddToAnki: onAddToAnki,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A sentence note needs the readings and glosses, so the button waits for
  /// the gloss, and for it to have found a word (D6b.3).
  bool get _canAddSentence {
    if (ocrState case OcrText(gloss: final gloss?)) {
      return gloss.hasMatches;
    }
    return false;
  }

  /// The sheet covers the bubble it is about, so it shows what it read. The
  /// fixed height is what lets `BgraImageView` (a `SizedBox.expand`) live in
  /// a `ListView`.
  Widget? _cropThumbnail() {
    final crop = switch (ocrState) {
      OcrIdle() => null,
      OcrRunning(:final crop) ||
      OcrText(:final crop) ||
      OcrFailed(:final crop) => crop,
    };
    if (crop == null) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        key: const Key('ocr.crop'),
        height: 96,
        child: BgraImageView(image: crop),
      ),
    );
  }

  Widget _ocrLine(ThemeData theme) {
    return switch (ocrState) {
      OcrIdle() => const SizedBox.shrink(),
      OcrRunning() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Reading the bubble…'),
          ],
        ),
      ),
      OcrFailed(:final message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: TextStyle(color: theme.colorScheme.error)),
      ),
      OcrText(:final text, :final gloss) => _TappableLine(
        text: text,
        gloss: gloss,
        highlight: _highlightRange(),
        onTapCharacter: onTapCharacter,
      ),
    };
  }

  /// The matched surface of the best (longest) result, so the reader sees
  /// which characters the entry covers. UTF-16 offsets, end exclusive.
  (int, int)? _highlightRange() {
    final state = lookupState;
    if (state is LookupResults && state.results.isNotEmpty) {
      final r = state.results.first;
      return (r.start, r.start + r.length);
    }
    if (state is LookupLoading) {
      return (state.index, state.index + 1);
    }
    return null;
  }
}

/// The OCR line: one tap target per code point. The cell is keyed and
/// reported by the code point's UTF-16 start offset, so a surrogate pair
/// (𠮷, two units) is one cell and a tap on it never sends a mid-character
/// index.
///
/// Until the [gloss] arrives the cells are laid out as they always were. With
/// it, each word the dictionary recognised becomes a column: readings over
/// its kanji, the cells, an underline (two colours alternating from word to
/// word) and its first gloss. Text the dictionary did not recognise stays
/// plain cells. Taps are unchanged: a lookup starts at the tapped character
/// whatever the cut (C15), so a wrong cut costs nothing.
class _TappableLine extends StatelessWidget {
  const _TappableLine({
    required this.text,
    required this.gloss,
    required this.highlight,
    required this.onTapCharacter,
  });

  /// Widest a gloss grows before it wraps, so a long one cannot push its
  /// neighbours off the line.
  static const double glossMaxWidth = 160;

  final String text;
  final LineGloss? gloss;
  final (int, int)? highlight;
  final void Function(int index) onTapCharacter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall?.japanese;
    final rubyStyle = theme.textTheme.labelSmall?.japanese.copyWith(
      height: 1.2,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final spans = gloss?.spans;
    if (spans == null) {
      return Wrap(
        children: [
          for (final (start, glyph) in _cells(text, 0))
            _cell(theme, style, start, glyph),
        ],
      );
    }
    // Every column reserves the ruby row when any word has readings, so
    // plain text and words share one baseline.
    final rubyHeight = spans.any((s) => s.matched && s.ruby.any(_hasRuby))
        ? (rubyStyle?.fontSize ?? 11) * 1.2
        : 0.0;
    var ordinal = 0;
    return Wrap(
      children: [
        for (final span in spans)
          if (span.matched)
            _wordColumn(theme, style, rubyStyle, rubyHeight, span, ordinal++)
          else
            for (final (start, glyph) in _cells(span.surface, span.start))
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: rubyHeight),
                  _cell(theme, style, start, glyph),
                ],
              ),
      ],
    );
  }

  static bool _hasRuby(RubySegment s) => s.ruby != null;

  Widget _wordColumn(
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
    var offset = span.start;
    final segments = <Widget>[];
    for (final segment in span.ruby) {
      final ruby = segment.ruby;
      segments.add(
        Column(
          mainAxisSize: MainAxisSize.min,
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
                  _cell(theme, style, start, glyph),
              ],
            ),
          ],
        ),
      );
      offset += segment.text.length;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          key: Key('ocr.span.${span.start}'),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: underline, width: 2)),
          ),
          // A word wider than the sheet (a long inflected chain) shrinks to
          // fit rather than overflowing.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: segments),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: glossMaxWidth),
          child: Text(
            span.gloss ?? '',
            key: Key('ocr.gloss.${span.start}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _cell(ThemeData theme, TextStyle? style, int start, String glyph) {
    final (from, to) = highlight ?? (-1, -1);
    return InkWell(
      key: Key('ocr.char.$start'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => onTapCharacter(start),
      // No `alignment` on the Container: that would make each cell
      // fill the row. Align with factors sizes to the glyph, and the
      // min constraints give the 32x44 tap target.
      child: Container(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: start < to && start + glyph.length > from
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
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
