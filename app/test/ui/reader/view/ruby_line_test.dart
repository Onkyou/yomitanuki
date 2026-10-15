import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/ui/reader/view/ruby_line.dart';

GlossSpan _word(int start, String surface, [String? ruby]) => GlossSpan(
  start: start,
  length: surface.length,
  surface: surface,
  reading: ruby ?? surface,
  gloss: 'g',
  glossShort: 'g',
  baseForm: surface,
  ruby: [RubySegment(surface, ruby)],
);

GlossSpan _plain(int start, String surface) => GlossSpan(
  start: start,
  length: surface.length,
  surface: surface,
  ruby: [RubySegment(surface)],
);

Future<void> _pump(
  WidgetTester tester,
  String text,
  List<GlossSpan>? spans, {
  (int, int)? highlight,
  void Function(int index)? onTap,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RubyLine(
          text: text,
          spans: spans,
          highlight: highlight,
          onTapCharacter: onTap ?? (_) {},
        ),
      ),
    ),
  );
}

Rect _cell(WidgetTester tester, int start) =>
    tester.getRect(find.byKey(Key('ocr.char.$start')));

int _pills(WidgetTester tester) {
  final scheme = Theme.of(tester.element(find.byType(RubyLine))).colorScheme;
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((b) {
    final d = b.decoration;
    return d is BoxDecoration && d.color == scheme.primaryContainer;
  }).length;
}

void main() {
  // 魔王を倒した勇者, cut as the glosser would with a fuller dictionary.
  const line = '魔王を倒した勇者';
  final spans = [
    _word(0, '魔王', 'まおう'),
    _plain(2, 'を'),
    _word(3, '倒した', 'たおした'),
    _word(6, '勇者', 'ゆうしゃ'),
  ];

  testWidgets('eight characters fit one row on a 375 px phone', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, line, spans);

    expect(tester.takeException(), isNull);
    final tops = {for (var i = 0; i < line.length; i++) _cell(tester, i).top};
    expect(tops, hasLength(1));
    expect(_cell(tester, 7).right, lessThanOrEqualTo(375));
  });

  testWidgets('a cell is as wide as its glyph and at least 52 tall', (
    tester,
  ) async {
    await _pump(tester, line, spans);
    final glyph = Theme.of(tester.element(find.byType(RubyLine)))
        .textTheme
        .headlineSmall!
        .fontSize!;

    for (var i = 0; i < line.length; i++) {
      final size = _cell(tester, i).size;
      expect(size.width, lessThanOrEqualTo(glyph + 2), reason: 'cell $i');
      expect(size.height, greaterThanOrEqualTo(52), reason: 'cell $i');
    }
  });

  testWidgets('the characters of a word sit side by side without a gap', (
    tester,
  ) async {
    await _pump(tester, line, spans);

    expect(_cell(tester, 1).left, closeTo(_cell(tester, 0).right, 0.5));
  });

  testWidgets('a reading wider than its kanji does not centre the cells', (
    tester,
  ) async {
    await _pump(tester, '九', [_word(0, '九', 'ながいよみがな')]);

    expect(
      _cell(tester, 0).left,
      closeTo(tester.getTopLeft(find.byKey(const Key('ocr.ruby.0'))).dx, 0.5),
    );
  });

  testWidgets('neighbouring words are 4 px apart', (tester) async {
    await _pump(tester, '魔王勇者', [_word(0, '魔王', 'まおう'), _word(2, '勇者')]);

    expect(_cell(tester, 2).left - _cell(tester, 1).right, closeTo(4, 0.5));
  });

  testWidgets('tapping each character reports its UTF-16 start', (
    tester,
  ) async {
    final taps = <int>[];
    // 𠮷 is one code point, two code units.
    await _pump(tester, '魔𠮷王を', [
      _word(0, '魔𠮷王'),
      _plain(4, 'を'),
    ], onTap: taps.add);

    for (final start in [0, 1, 3, 4]) {
      await tester.tap(find.byKey(Key('ocr.char.$start')));
    }

    expect(taps, [0, 1, 3, 4]);
  });

  testWidgets('before the gloss every character is a plain cell', (
    tester,
  ) async {
    final taps = <int>[];
    await _pump(tester, '食べる', null, onTap: taps.add);

    await tester.tap(find.byKey(const Key('ocr.char.2')));

    expect(taps, [2]);
    expect(find.byKey(const Key('ocr.span.0')), findsNothing);
    expect(find.byKey(const Key('ocr.ruby.0')), findsNothing);
  });

  testWidgets('a 30-character line wraps without an exception', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final text = '魔王' * 15;
    await _pump(tester, text, [
      for (var i = 0; i < 15; i++) _word(i * 2, '魔王', 'まおう'),
    ]);

    expect(tester.takeException(), isNull);
    expect(
      _cell(tester, 29).top,
      greaterThan(_cell(tester, 0).top + 52),
      reason: 'a second row',
    );
    expect(_cell(tester, 29).right, lessThanOrEqualTo(375));
  });

  testWidgets('a word wider than the line scales down instead of overflowing', (
    tester,
  ) async {
    final text = 'あ' * 40;
    await _pump(tester, text, [_word(0, text)]);

    expect(tester.takeException(), isNull);
    final fitted = find.ancestor(
      of: find.byKey(const Key('ocr.span.0')),
      matching: find.byType(FittedBox),
    );
    expect(tester.getSize(fitted).width, lessThanOrEqualTo(800));
  });

  testWidgets('a highlight over a whole word is one pill, not one per cell', (
    tester,
  ) async {
    await _pump(tester, line, spans, highlight: (0, 2));

    expect(_pills(tester), 1);
    expect(
      find.ancestor(
        of: find.byKey(const Key('ocr.span.0')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).color != null,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a highlight over part of a word marks those cells', (
    tester,
  ) async {
    await _pump(tester, line, spans, highlight: (1, 2));

    expect(_pills(tester), 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('ocr.char.1')),
        matching: find.byType(DecoratedBox),
      ),
      findsWidgets,
    );
  });

  testWidgets('a highlight over plain text marks its cells', (tester) async {
    await _pump(tester, line, spans, highlight: (2, 3));

    expect(_pills(tester), 1);
  });

  testWidgets('no highlight, no pill', (tester) async {
    await _pump(tester, line, spans);

    expect(_pills(tester), 0);
  });
}
