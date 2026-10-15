import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../view_model/reader_state.dart';
import 'japanese_text.dart';

/// The dictionary half of the OCR sheet (D6e.6): the longest match as a card
/// that is a reminder first, shorter matches as one-line rows that open into
/// the full card. The longest match has no "Add to Anki" of its own, the
/// sheet's bottom bar carries it; a shorter match keeps its button in the
/// opened card.
class LookupResultsView extends StatefulWidget {
  const LookupResultsView({
    required this.state,
    required this.onAddToAnki,
    super.key,
  });

  final LookupState state;
  final void Function(LookupResult result) onAddToAnki;

  @override
  State<LookupResultsView> createState() => _LookupResultsViewState();
}

class _LookupResultsViewState extends State<LookupResultsView> {
  final _firstCardTop = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_hasResults(widget.state)) {
      _revealFirstCard();
    }
  }

  @override
  void didUpdateWidget(LookupResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = widget.state;
    final old = oldWidget.state;
    if (_hasResults(state) &&
        !(old is LookupResults &&
            identical(old.results, (state as LookupResults).results))) {
      _revealFirstCard();
    }
  }

  static bool _hasResults(LookupState state) =>
      state is LookupResults && state.results.isNotEmpty;

  /// The card lands under the word list and may be below the fold of the
  /// sheet's list; bring its top row into view, and leave the list alone when
  /// it is there already.
  void _revealFirstCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _firstCardTop.currentContext;
      if (context == null || !context.mounted) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (widget.state) {
      LookupIdle() => const SizedBox.shrink(),
      LookupLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: LinearProgressIndicator(),
      ),
      LookupFailed(:final message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message, style: TextStyle(color: theme.colorScheme.error)),
      ),
      LookupResults(:final results) when results.isEmpty => Padding(
        key: const Key('lookup.empty'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No dictionary entry starts here.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      LookupResults(:final results, :final kanji) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, result) in results.indexed)
            // Keyed by the result, so a new lookup starts every card and row
            // collapsed again.
            i == 0
                ? _ResultCard(
                    key: ObjectKey(result),
                    index: i,
                    result: result,
                    kanji: _kanjiOf(result, kanji),
                    topKey: _firstCardTop,
                  )
                : _LaterResult(
                    key: ObjectKey(result),
                    index: i,
                    result: result,
                    kanji: _kanjiOf(result, kanji),
                    onAddToAnki: () => widget.onAddToAnki(result),
                  ),
        ],
      ),
    };
  }

  /// One card per distinct kanji in the surface (人々 or 日々 would otherwise
  /// repeat a card).
  static List<KanjiEntry> _kanjiOf(
    LookupResult result,
    Map<String, KanjiEntry> kanji,
  ) => [
    for (final literal in {
      for (final rune in result.surface.runes) String.fromCharCode(rune),
    })
      ?kanji[literal],
  ];
}

/// The senses of [result] in the order to show them: the ones the match can
/// be first (WP6d `matchedSenseIndexes`, out-of-range ones ignored), then the
/// rest in dictionary order.
List<Sense> _sensesInOrder(LookupResult result) {
  final senses = result.entry.senses;
  final first = [
    for (final i in result.matchedSenseIndexes)
      if (i >= 0 && i < senses.length) i,
  ];
  return [
    for (final i in first) senses[i],
    for (final (i, sense) in senses.indexed)
      if (!first.contains(i)) sense,
  ];
}

/// A match after the first: `headword 【reading】 first gloss` on one line;
/// tap opens the full card, with its "Add to Anki".
class _LaterResult extends StatefulWidget {
  const _LaterResult({
    required this.index,
    required this.result,
    required this.kanji,
    required this.onAddToAnki,
    super.key,
  });

  final int index;
  final LookupResult result;
  final List<KanjiEntry> kanji;
  final VoidCallback onAddToAnki;

  @override
  State<_LaterResult> createState() => _LaterResultState();
}

class _LaterResultState extends State<_LaterResult> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_open) {
      return _ResultCard(
        index: widget.index,
        result: widget.result,
        kanji: widget.kanji,
        onAddToAnki: widget.onAddToAnki,
      );
    }
    final theme = Theme.of(context);
    final entry = widget.result.entry;
    final senses = _sensesInOrder(widget.result);
    final gloss = senses.isEmpty || senses.first.glosses.isEmpty
        ? ''
        : senses.first.glosses.first;
    return InkWell(
      key: Key('lookup.row.${widget.index}'),
      onTap: () => setState(() => _open = true),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${entry.headword}【${entry.reading}】',
                      style: theme.textTheme.titleMedium?.japanese,
                    ),
                    const WidgetSpan(child: SizedBox(width: 8)),
                    TextSpan(
                      text: gloss,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.expand_more,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatefulWidget {
  const _ResultCard({
    required this.index,
    required this.result,
    required this.kanji,
    this.onAddToAnki,
    this.topKey,
    super.key,
  });

  /// How many senses a card shows before "+N more senses".
  static const shownSenses = 3;

  final int index;
  final LookupResult result;
  final List<KanjiEntry> kanji;

  /// The card's own "Add to Anki"; null for the longest match, whose button
  /// is the sheet's bottom bar.
  final VoidCallback? onAddToAnki;

  /// Marks the card's top row so the view can scroll it into view.
  final GlobalKey? topKey;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _allSenses = false;
  bool _showKanji = false;

  /// The first card keeps the plain keys the tests and the integration flows
  /// use; a card opened from a row gets its index appended.
  Key _key(String name) =>
      Key(widget.index == 0 ? name : '$name.${widget.index}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final index = widget.index;
    final entry = result.entry;
    final otherForm = result.matchedReading != entry.reading;
    final senses = _sensesInOrder(result);
    final shown = _allSenses
        ? senses
        : senses.take(_ResultCard.shownSenses).toList();
    final hidden = senses.length - shown.length;
    final onAddToAnki = widget.onAddToAnki;
    return Card(
      key: Key('lookup.card.$index'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: widget.topKey,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.ideographic,
              children: [
                // A form that is not the entry's headword reads differently
                // (ビール is read ビール, not 麦酒's ばくしゅ): lead with the
                // form that matched and keep the entry's own spelling below.
                if (otherForm)
                  Expanded(
                    child: Text(
                      result.matchedReading,
                      style: theme.textTheme.headlineSmall?.japanese,
                    ),
                  )
                else ...[
                  Text(
                    entry.headword,
                    style: theme.textTheme.headlineSmall?.japanese,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.reading,
                      style: theme.textTheme.titleMedium?.japanese.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (entry.isCommon)
                  Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  ),
              ],
            ),
            if (otherForm)
              Text(
                '${entry.headword}【${entry.reading}】',
                key: Key('lookup.matched.$index'),
                style: theme.textTheme.titleMedium?.japanese.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    result.surface,
                    style: theme.textTheme.bodySmall?.japanese,
                  ),
                  for (final reason in result.reasons) _Badge(label: reason),
                ],
              ),
            ],
            const SizedBox(height: 8),
            for (final (n, sense) in shown.indexed)
              _SenseRow(number: n + 1, sense: sense),
            if (hidden > 0)
              InkWell(
                key: _key('lookup.moreSenses'),
                onTap: () => setState(() => _allSenses = true),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '+$hidden more ${hidden == 1 ? 'sense' : 'senses'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.kanji.isNotEmpty) ...[
              InkWell(
                key: _key('lookup.kanji.toggle'),
                onTap: () => setState(() => _showKanji = !_showKanji),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _showKanji ? 'Kanji ⌄' : 'Kanji ›',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
              ),
              if (_showKanji)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in widget.kanji) _KanjiCard(entry: k),
                  ],
                ),
            ],
            if (onAddToAnki != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: Key('anki.add.$index'),
                  onPressed: onAddToAnki,
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Add to Anki'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One sense: `n. glosses`, and its parts of speech as one small muted tag at
/// the end of the line.
class _SenseRow extends StatelessWidget {
  const _SenseRow({required this.number, required this.sense});

  final int number;
  final Sense sense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$number. ${sense.glosses.join(', ')}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (sense.partsOfSpeech.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    sense.partsOfSpeech.join(', '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A read-only label (a deinflection step); not a Chip, which is a control.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _KanjiCard extends StatelessWidget {
  const _KanjiCard({required this.entry});

  final KanjiEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readings = [
      ...entry.onReadings,
      ...entry.kunReadings,
    ].take(4).join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.literal, style: theme.textTheme.titleLarge?.japanese),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.meanings.take(3).join(', '),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  readings,
                  style: theme.textTheme.bodySmall?.japanese.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
