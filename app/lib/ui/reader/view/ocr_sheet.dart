import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/lookup_result.dart';
import '../view_model/reader_state.dart';
import 'bgra_image_view.dart';
import 'crop_zoom.dart';
import 'lookup_results_view.dart';
import 'ruby_line.dart';
import 'word_list.dart';

/// The bottom panel that opens when a block is tapped (D6e): a grab handle,
/// the bubble's crop and the OCR line as one ruby sentence with its
/// translation under it, one row per recognised word, the dictionary card for
/// the tapped character, and the Anki actions in a bar that stays put. Every
/// character is its own tap target (C15: lookups start at the tapped
/// character). Vertical bubble text is shown horizontally in v1.
class OcrSheet extends StatelessWidget {
  const OcrSheet({
    required this.ocrState,
    required this.lookupState,
    required this.translationActive,
    required this.translationNote,
    required this.showHint,
    required this.onTapCharacter,
    required this.onAddToAnki,
    required this.onAddSentence,
    required this.onDismissTranslationNote,
    required this.onClose,
    super.key,
  });

  /// Tallest a vertical bubble's crop gets, however tall the text beside it.
  static const double maxGutterHeight = 140;

  /// Tallest a horizontal bubble's crop gets.
  static const double maxBannerHeight = 72;

  final OcrState ocrState;
  final LookupState lookupState;

  /// A translation is running or has landed for this read (WP6c): while it
  /// has not landed yet the sheet shows a skeleton bar where it will be.
  final bool translationActive;

  /// One quiet line about why no translation comes (D6e.7); null for none.
  final String? translationNote;

  /// Show "Tap a character to look it up." (until the first lookup).
  final bool showHint;

  /// [index] is a UTF-16 offset into the OCR text, what `Dictionary.lookupAt`
  /// and `LookupResult.start` use.
  final void Function(int index) onTapCharacter;
  final void Function(LookupResult result) onAddToAnki;
  final VoidCallback onAddSentence;
  final VoidCallback onDismissTranslationNote;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    final spans = switch (ocrState) {
      OcrText(:final gloss) => gloss?.spans,
      _ => null,
    };
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
              _HandleRow(onClose: _close),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: [
                    _header(context, theme),
                    if (spans != null) ...[
                      const SizedBox(height: 8),
                      WordList(
                        spans: spans,
                        highlightStart: _highlightRange()?.$1,
                        onTapCharacter: onTapCharacter,
                      ),
                    ],
                    const SizedBox(height: 8),
                    LookupResultsView(
                      state: lookupState,
                      onAddToAnki: onAddToAnki,
                    ),
                    if (showHint)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Tap a character to look it up.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// The note is for this sheet only; whatever way it closes, it is done.
  void _close() {
    onDismissTranslationNote();
    onClose();
  }

  /// A sentence note needs the readings and glosses, so the button waits for
  /// the gloss, and for it to have found a word (D6b.3).
  bool get _canAddSentence {
    if (ocrState case OcrText(gloss: final gloss?)) {
      return gloss.hasMatches;
    }
    return false;
  }

  /// The actions under the thumb, outside the scrolling list (D6e.5).
  Widget _bottomBar() {
    final state = lookupState;
    final best = state is LookupResults && state.results.isNotEmpty
        ? state.results.first
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            key: const Key('anki.addSentence'),
            onPressed: _canAddSentence ? onAddSentence : null,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Add sentence'),
          ),
          const SizedBox(width: 8),
          // Expanded and Align rather than Spacer and Flexible: a Flexible
          // next to a Spacer is held to half the free width.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: best == null
                  ? null
                  : FilledButton.icon(
                      key: const Key('anki.addWord'),
                      onPressed: () => onAddToAnki(best),
                      icon: const Icon(Icons.add_card_outlined),
                      // The note's Word (D6d.1), the text the hand-over names.
                      label: Text(
                        'Add ${best.baseForm}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  BgraImage? get _crop => switch (ocrState) {
    OcrIdle() => null,
    OcrRunning(:final crop) ||
    OcrText(:final crop) ||
    OcrFailed(:final crop) => crop,
  };

  /// The crop and the text. A vertical bubble's crop is a gutter beside the
  /// line and its translation, as tall as they are (up to
  /// [maxGutterHeight]); a horizontal bubble's is a banner above them
  /// (D6e.4). The sheet covers the bubble, so it shows what it read. The
  /// translation note is under both, at full width.
  Widget _header(BuildContext context, ThemeData theme) {
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_ocrLine(theme), ?_translationLine(theme)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cropAndText(context, text),
        ?_translationNoteLine(context, theme),
      ],
    );
  }

  Widget _cropAndText(BuildContext context, Widget text) {
    final crop = _crop;
    if (crop == null) {
      return text;
    }
    // Tapping the picture opens it zoomable; announced as the button it is.
    Widget enlargeable(Widget picture) => Semantics(
      button: true,
      label: 'Bubble photo, enlarge',
      child: InkWell(
        key: const Key('ocr.crop'),
        onTap: () => unawaited(CropZoom.show(context, crop)),
        child: picture,
      ),
    );
    if (crop.height > crop.width) {
      // The text is the sizing child and the gutter is laid over its left
      // edge: the gutter's height is whatever the text's is, never the
      // picture's own size. Its width is fixed from the aspect at a typical
      // 100 px, because the text height it would depend on is known only
      // after the text has been laid out beside it; the picture is
      // letterboxed in the box.
      final width = (crop.width / crop.height * 100).clamp(36.0, 80.0);
      return Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(left: width + 12),
            child: text,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: width,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: maxGutterHeight),
                child: enlargeable(BgraImageView(image: crop)),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: (constraints.maxWidth * crop.height / crop.width).clamp(
              0.0,
              maxBannerHeight,
            ),
            child: enlargeable(BgraImageView(image: crop)),
          ),
        ),
        const SizedBox(height: 8),
        text,
      ],
    );
  }

  /// The English line under the Japanese (WP6c, D6e.3): muted, marked as a
  /// machine translation by its icon. A skeleton bar the same height while
  /// it is on its way, so a late landing does not move the rows under it.
  /// Nothing when translation is off or failed.
  Widget? _translationLine(ThemeData theme) {
    final state = ocrState;
    if (state is! OcrText) {
      return null;
    }
    final muted = theme.colorScheme.onSurfaceVariant;
    final translation = state.translation;
    if (translation == null) {
      return translationActive
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              // 20 high like one line of bodyMedium, the bar itself 16.
              child: SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Container(
                      key: const Key('ocr.translation.pending'),
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null;
    }
    if (translation.isEmpty) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.translate, size: 16, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translation,
              key: const Key('ocr.translation'),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _translationNoteLine(BuildContext context, ThemeData theme) {
    final note = translationNote;
    if (note == null || ocrState is! OcrText) {
      return null;
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            note,
            key: const Key('ocr.translation.note'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            onDismissTranslationNote();
            unawaited(Navigator.pushNamed(context, 'settings'));
          },
          child: const Text('Settings'),
        ),
      ],
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
      OcrText(:final text, :final gloss) => RubyLine(
        text: text,
        spans: gloss?.spans,
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

/// The grab handle with the close button at its right, and the swipe-down-to-
/// close gesture. Only this strip listens for the drag, so the list under it
/// scrolls undisturbed.
class _HandleRow extends StatefulWidget {
  const _HandleRow({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_HandleRow> createState() => _HandleRowState();
}

class _HandleRowState extends State<_HandleRow> {
  /// A downward fling faster than this closes the sheet, or a slow drag
  /// longer than [_closeDistance] (logical px per second, logical px).
  static const _closeVelocity = 700;
  static const _closeDistance = 80;

  double _dragged = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragged = 0,
      onVerticalDragUpdate: (details) => _dragged += details.delta.dy,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > _closeVelocity ||
            _dragged > _closeDistance) {
          widget.onClose();
        }
      },
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            Center(
              child: Container(
                key: const Key('ocr.handle'),
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                key: const Key('ocr.close'),
                tooltip: 'Back to the page',
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
