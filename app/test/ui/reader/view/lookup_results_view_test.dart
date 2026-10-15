import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/ui/reader/view/lookup_results_view.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_state.dart';

const _kanji = KanjiEntry(
  literal: '魔',
  meanings: ['evil spirit', 'devil'],
  onReadings: ['マ'],
  kunReadings: [],
);

DictionaryEntry _entry({
  String headword = '魔王',
  String reading = 'まおう',
  int senses = 5,
  List<String> pos = const ['n'],
}) => DictionaryEntry(
  id: 1,
  headword: headword,
  reading: reading,
  senses: [
    for (var i = 1; i <= senses; i++)
      Sense(glosses: ['gloss $i', 'alt $i'], partsOfSpeech: pos),
  ],
  isCommon: false,
);

LookupResult _result(
  DictionaryEntry entry, {
  List<int> matched = const [],
  String? surface,
}) => LookupResult(
  start: 0,
  length: (surface ?? entry.headword).length,
  surface: surface ?? entry.headword,
  baseForm: entry.headword,
  matchedReading: entry.reading,
  reasons: const [],
  entry: entry,
  matchedSenseIndexes: matched,
);

LookupState _state(
  List<LookupResult> results, {
  Map<String, KanjiEntry> kanji = const {},
}) => LookupResults(index: 0, results: results, kanji: kanji);

Future<void> _pump(
  WidgetTester tester,
  LookupState state, {
  void Function(LookupResult)? onAdd,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: LookupResultsView(state: state, onAddToAnki: onAdd ?? (_) {}),
      ),
    ),
  ),
);

void main() {
  group('the first card is a reminder (D6e.6)', () {
    testWidgets('three senses of five, then "+2 more senses"', (tester) async {
      await _pump(tester, _state([_result(_entry())]));

      expect(find.textContaining('gloss 1'), findsOneWidget);
      expect(find.textContaining('gloss 3'), findsOneWidget);
      expect(find.textContaining('gloss 4'), findsNothing);
      expect(find.text('+2 more senses'), findsOneWidget);
    });

    testWidgets('tapping the row shows every sense', (tester) async {
      await _pump(tester, _state([_result(_entry())]));

      await tester.tap(find.byKey(const Key('lookup.moreSenses')));
      await tester.pump();

      expect(find.textContaining('gloss 5'), findsOneWidget);
      expect(find.byKey(const Key('lookup.moreSenses')), findsNothing);
    });

    testWidgets('the "more" and "Kanji" rows are 44 pt targets', (
      tester,
    ) async {
      await _pump(tester, _state([_result(_entry())], kanji: {'魔': _kanji}));

      expect(
        tester.getSize(find.byKey(const Key('lookup.moreSenses'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.byKey(const Key('lookup.kanji.toggle'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('three senses or fewer have no "more" row', (tester) async {
      await _pump(tester, _state([_result(_entry(senses: 3))]));

      expect(find.byKey(const Key('lookup.moreSenses')), findsNothing);
    });

    testWidgets('one more is "+1 more sense"', (tester) async {
      await _pump(tester, _state([_result(_entry(senses: 4))]));

      expect(find.text('+1 more sense'), findsOneWidget);
    });

    testWidgets('the matched senses come first, numbered in the order shown', (
      tester,
    ) async {
      await _pump(
        tester,
        _state([
          _result(_entry(), matched: [3, 1]),
        ]),
      );

      final texts = tester
          .widgetList<Text>(find.textContaining('gloss '))
          .map((t) => t.data!)
          .toList();
      expect(texts, [
        '1. gloss 4, alt 4',
        '2. gloss 2, alt 2',
        '3. gloss 1, alt 1',
      ]);
      expect(find.text('+2 more senses'), findsOneWidget);
    });

    testWidgets('the part of speech is one small muted tag after the sense', (
      tester,
    ) async {
      await _pump(
        tester,
        _state([
          _result(_entry(senses: 1, pos: const ['v1', 'vt'])),
        ]),
      );

      final tag = find.text('v1, vt');
      expect(tag, findsOneWidget);
      final theme = Theme.of(tester.element(find.byType(LookupResultsView)));
      expect(
        tester.widget<Text>(tag).style!.fontSize,
        theme.textTheme.labelSmall!.fontSize,
      );
      expect(
        find.ancestor(
          of: tag,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration).color ==
                    theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(tag).dx,
        greaterThan(tester.getTopLeft(find.textContaining('gloss 1')).dx),
      );
    });

    testWidgets('a sense without tags has no tag', (tester) async {
      await _pump(tester, _state([_result(_entry(senses: 1, pos: const []))]));

      expect(find.textContaining('gloss 1'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });

    testWidgets('the card has no Add to Anki, the bottom bar does', (
      tester,
    ) async {
      await _pump(tester, _state([_result(_entry())]));

      expect(find.byKey(const Key('anki.add.0')), findsNothing);
      expect(find.text('Add to Anki'), findsNothing);
    });

    testWidgets('kanji stay hidden until "Kanji" is tapped', (tester) async {
      await _pump(tester, _state([_result(_entry())], kanji: {'魔': _kanji}));

      expect(find.byKey(const Key('lookup.kanji.toggle')), findsOneWidget);
      expect(find.textContaining('evil spirit'), findsNothing);

      await tester.tap(find.byKey(const Key('lookup.kanji.toggle')));
      await tester.pump();

      expect(find.textContaining('evil spirit'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lookup.kanji.toggle')));
      await tester.pump();

      expect(find.textContaining('evil spirit'), findsNothing);
    });

    testWidgets('no kanji data, no "Kanji" row', (tester) async {
      await _pump(tester, _state([_result(_entry())]));

      expect(find.byKey(const Key('lookup.kanji.toggle')), findsNothing);
    });

    testWidgets('the headword and reading lead, deinflection stays', (
      tester,
    ) async {
      final r = LookupResult(
        start: 0,
        length: 3,
        surface: '食べた',
        baseForm: '食べる',
        matchedReading: 'たべる',
        reasons: const ['past'],
        entry: _entry(headword: '食べる', reading: 'たべる', senses: 1),
        matchedSenseIndexes: const [0],
      );
      await _pump(tester, _state([r]));

      expect(find.text('食べる'), findsOneWidget);
      expect(find.text('たべる'), findsOneWidget);
      expect(find.text('past'), findsOneWidget);
    });
  });

  group('shorter matches are one line (D6e.6)', () {
    final long = _result(_entry());
    final short = _result(
      _entry(headword: '魔', reading: 'ま', senses: 2),
      surface: '魔',
    );

    testWidgets('collapsed: headword 【reading】 first gloss, no Add', (
      tester,
    ) async {
      await _pump(tester, _state([long, short]));

      final row = find.byKey(const Key('lookup.row.1'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('魔【ま】', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('gloss 1', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('anki.add.1')), findsNothing);
      expect(find.byKey(const Key('lookup.row.0')), findsNothing);
    });

    testWidgets('tapping the row opens the full card with its own Add', (
      tester,
    ) async {
      final added = <LookupResult>[];
      await _pump(tester, _state([long, short]), onAdd: added.add);

      await tester.tap(find.byKey(const Key('lookup.row.1')));
      await tester.pump();

      expect(find.byKey(const Key('lookup.row.1')), findsNothing);
      expect(find.textContaining('gloss 2'), findsWidgets);
      await tester.ensureVisible(find.byKey(const Key('anki.add.1')));
      await tester.tap(find.byKey(const Key('anki.add.1')));
      expect(added, [short]);
    });

    testWidgets('a new lookup collapses the rows again', (tester) async {
      await _pump(tester, _state([long, short]));
      await tester.tap(find.byKey(const Key('lookup.row.1')));
      await tester.pump();

      await _pump(
        tester,
        _state([
          _result(_entry()),
          _result(_entry(headword: '魔', reading: 'ま', senses: 2)),
        ]),
      );

      expect(find.byKey(const Key('lookup.row.1')), findsOneWidget);
    });

    testWidgets('the row is one line however long the gloss', (tester) async {
      final wordy = _result(
        DictionaryEntry(
          id: 2,
          headword: '魔',
          reading: 'ま',
          senses: [
            Sense(glosses: ['very long ' * 40], partsOfSpeech: const ['n']),
          ],
          isCommon: false,
        ),
        surface: '魔',
      );
      await _pump(tester, _state([long, wordy]));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('lookup.row.1'))).height,
        lessThanOrEqualTo(56),
      );
    });

    testWidgets('the row leads with the matched sense', (tester) async {
      final r = _result(
        _entry(headword: '魔', reading: 'ま', senses: 3),
        surface: '魔',
        matched: [2],
      );
      await _pump(tester, _state([long, r]));

      expect(
        find.descendant(
          of: find.byKey(const Key('lookup.row.1')),
          matching: find.textContaining('gloss 3', findRichText: true),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('with no result there is no card and no hint', (tester) async {
    await _pump(tester, const LookupIdle());

    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('Tap'), findsNothing);
  });

  group('landing', () {
    Future<void> pumpList(WidgetTester tester, LookupState state) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              // Not a ListView: that builds lazily and the card would not
              // exist yet, as in the sheet's shrink-wrapped list it does.
              child: SingleChildScrollView(
                key: const Key('list'),
                child: Column(
                  children: [
                    const SizedBox(width: double.infinity, height: 800),
                    LookupResultsView(state: state, onAddToAnki: (_) {}),
                    const SizedBox(width: double.infinity, height: 800),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the first card\'s top is scrolled into view', (tester) async {
      await pumpList(tester, const LookupIdle());
      final viewport = tester.getRect(find.byKey(const Key('list')));

      await pumpList(tester, _state([_result(_entry())]));
      await tester.pumpAndSettle();

      final top = tester.getTopLeft(find.byKey(const Key('lookup.card.0')));
      expect(top.dy, greaterThanOrEqualTo(viewport.top));
      expect(top.dy, lessThan(viewport.bottom));
    });

    testWidgets('a card already in view does not move the list', (
      tester,
    ) async {
      await pumpList(tester, const LookupIdle());
      await tester.drag(find.byKey(const Key('list')), const Offset(0, -700));
      await tester.pumpAndSettle();
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      // The card will land at 800 - 700 = 100 px into a 300 px viewport.
      expect(before, 700);

      await pumpList(tester, _state([_result(_entry())]));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        before,
      );
    });
  });
}
