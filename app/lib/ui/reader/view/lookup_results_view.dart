import 'package:flutter/material.dart';

import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../view_model/reader_state.dart';
import 'japanese_text.dart';

/// The dictionary half of the OCR sheet: one card per match, longest
/// surface first, each with its own "Add to Anki".
class LookupResultsView extends StatelessWidget {
  const LookupResultsView({
    required this.state,
    required this.onAddToAnki,
    super.key,
  });

  final LookupState state;
  final void Function(LookupResult result) onAddToAnki;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (state) {
      LookupIdle() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Tap a character to look it up.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
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
            _ResultCard(
              index: i,
              result: result,
              kanji: [
                // One card per distinct kanji in the surface (人々 or 日々
                // would otherwise repeat a card).
                for (final literal in {
                  for (final rune in result.surface.runes)
                    String.fromCharCode(rune),
                })
                  ?kanji[literal],
              ],
              onAddToAnki: () => onAddToAnki(result),
            ),
        ],
      ),
    };
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.index,
    required this.result,
    required this.kanji,
    required this.onAddToAnki,
  });

  final int index;
  final LookupResult result;
  final List<KanjiEntry> kanji;
  final VoidCallback onAddToAnki;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = result.entry;
    final otherForm = result.matchedReading != entry.reading;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            for (final (n, sense) in entry.senses.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${n + 1}. ${sense.glosses.join(', ')}'
                  '${sense.partsOfSpeech.isEmpty ? '' : '  ·  ${sense.partsOfSpeech.join(', ')}'}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            if (kanji.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final k in kanji) _KanjiCard(entry: k)],
              ),
            ],
            const SizedBox(height: 12),
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
        ),
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
