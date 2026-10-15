import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/ui/reader/view/word_list.dart';

GlossSpan _word(
  int start,
  String surface, {
  String? reading,
  String gloss = 'a gloss',
  int extra = 0,
  bool function = false,
}) => GlossSpan(
  start: start,
  length: surface.length,
  surface: surface,
  reading: reading ?? surface,
  gloss: gloss,
  glossShort: gloss,
  extraSenses: extra,
  isFunctionWord: function,
  baseForm: surface,
  ruby: [RubySegment(surface)],
);

Future<void> _pump(
  WidgetTester tester,
  List<GlossSpan> spans, {
  int? highlightStart,
  void Function(int)? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: WordList(
        spans: spans,
        highlightStart: highlightStart,
        onTapCharacter: onTap ?? (_) {},
      ),
    ),
  ),
);

Color? _background(WidgetTester tester, int start) {
  final material = tester.widget<Material>(
    find
        .ancestor(
          of: find.byKey(Key('ocr.word.$start')),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color;
}

void main() {
  testWidgets('a row per matched content word, 44 high', (tester) async {
    await _pump(tester, [
      _word(0, '魔王', reading: 'まおう'),
      GlossSpan(
        start: 2,
        length: 1,
        surface: 'を',
        ruby: const [RubySegment('を')],
      ),
      _word(3, 'は', function: true),
      _word(4, '勇者', reading: 'ゆうしゃ'),
    ]);

    expect(find.byKey(const Key('ocr.word.0')), findsOneWidget);
    expect(find.byKey(const Key('ocr.word.2')), findsNothing);
    expect(find.byKey(const Key('ocr.word.3')), findsNothing);
    expect(find.byKey(const Key('ocr.word.4')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('ocr.word.0'))).height, 44);
  });

  testWidgets('a row has the surface, the reading and the gloss', (
    tester,
  ) async {
    await _pump(tester, [_word(0, '魔王', reading: 'まおう', gloss: 'Satan')]);

    expect(find.textContaining('魔王', findRichText: true), findsOneWidget);
    expect(find.textContaining('まおう', findRichText: true), findsOneWidget);
    expect(find.text('Satan'), findsOneWidget);
  });

  testWidgets('a kana word does not repeat itself as its reading', (
    tester,
  ) async {
    await _pump(tester, [_word(0, 'ビール', gloss: 'beer')]);

    final text = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const Key('ocr.word.0')),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(text.text.toPlainText(), 'ビール');
  });

  testWidgets('+N appears only when more senses apply', (tester) async {
    await _pump(tester, [_word(0, '魔王', extra: 2), _word(2, '勇者')]);

    expect(
      find.descendant(
        of: find.byKey(const Key('ocr.word.0')),
        matching: find.text('+2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('ocr.word.2')),
        matching: find.textContaining('+'),
      ),
      findsNothing,
    );
  });

  testWidgets('a long gloss stays on one line with an ellipsis', (
    tester,
  ) async {
    await _pump(tester, [_word(0, '魔王', gloss: 'very long ' * 30)]);

    final gloss = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('ocr.word.0')),
        matching: find.textContaining('very long'),
      ),
    );
    expect(gloss.maxLines, 1);
    expect(gloss.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the word being looked up is marked, wherever in it', (
    tester,
  ) async {
    await _pump(tester, [_word(0, '魔王'), _word(2, '勇者')], highlightStart: 1);
    final scheme = Theme.of(tester.element(find.byType(WordList))).colorScheme;

    expect(_background(tester, 0), scheme.primaryContainer);
    expect(_background(tester, 2), isNot(scheme.primaryContainer));
  });

  testWidgets('no lookup, no marked row', (tester) async {
    await _pump(tester, [_word(0, '魔王')]);
    final scheme = Theme.of(tester.element(find.byType(WordList))).colorScheme;

    expect(_background(tester, 0), isNot(scheme.primaryContainer));
  });

  testWidgets('tapping a row reports the first character of the word', (
    tester,
  ) async {
    final taps = <int>[];
    await _pump(tester, [_word(0, '魔王'), _word(2, '勇者')], onTap: taps.add);

    await tester.tap(find.byKey(const Key('ocr.word.2')));

    expect(taps, [2]);
  });
}
