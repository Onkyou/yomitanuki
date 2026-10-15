import 'package:flutter/material.dart';

import '../../../domain/models/line_gloss.dart';
import 'japanese_text.dart';

/// One row per word the dictionary recognised, under the line: surface,
/// reading, a one-line gloss and "+N" when more senses apply (D6e.1).
/// Particles and auxiliaries keep their underline in the line but get no row.
/// Tapping a row is tapping the word's first character (C15).
class WordList extends StatelessWidget {
  const WordList({
    required this.spans,
    required this.highlightStart,
    required this.onTapCharacter,
    super.key,
  });

  static const double rowHeight = 44;

  final List<GlossSpan> spans;

  /// UTF-16 offset where the lookup on screen starts; the row of the word that
  /// contains it is marked.
  final int? highlightStart;
  final void Function(int index) onTapCharacter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final span in spans)
          if (span.matched && !span.isFunctionWord)
            _WordRow(
              span: span,
              selected: _contains(span, highlightStart),
              onTap: () => onTapCharacter(span.start),
            ),
      ],
    );
  }

  static bool _contains(GlossSpan span, int? at) =>
      at != null && at >= span.start && at < span.start + span.length;
}

/// Widest the surface-and-reading part of a row grows, so a long word cannot
/// push the gloss off the line.
const double _maxWordColumnWidth = 220;

class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.span,
    required this.selected,
    required this.onTap,
  });

  final GlossSpan span;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // A Material per row: ink on the sheet's Material would paint under the
    // scrolling list and outside its viewport.
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('ocr.word.${span.start}'),
        onTap: onTap,
        child: SizedBox(
          height: WordList.rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _maxWordColumnWidth,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: span.surface,
                          style: theme.textTheme.titleMedium?.japanese,
                        ),
                        // A kana word reads as itself; saying so twice is noise.
                        if (span.reading != span.surface) ...[
                          const WidgetSpan(child: SizedBox(width: 8)),
                          TextSpan(
                            text: span.reading,
                            style: theme.textTheme.bodySmall?.japanese.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    span.glossShort ?? '',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (span.extraSenses > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '+${span.extraSenses}',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
