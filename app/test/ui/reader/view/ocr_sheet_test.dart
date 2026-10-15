import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/domain/use_cases/line_glosser.dart';
import 'package:yomitanuki/ui/reader/view/bgra_image_view.dart';
import 'package:yomitanuki/ui/reader/view/ocr_sheet.dart';
import 'package:yomitanuki/ui/reader/view/ruby_line.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_state.dart';

import '../../../fakes/fake_dictionary.dart';
import '../../../fakes/images.dart';

const _block = TextBlock(box: Rect.fromLTWH(10, 10, 20, 20), confidence: 0.9);

Future<void> _pumpSheet(
  WidgetTester tester,
  OcrState state, {
  LookupState lookup = const LookupIdle(),
  void Function(int index)? onTapCharacter,
  void Function(LookupResult result)? onAddToAnki,
  VoidCallback? onAddSentence,
  VoidCallback? onClose,
  bool translationActive = false,
  String? translationNote,
  VoidCallback? onDismissTranslationNote,
  bool showHint = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      routes: {'settings': (_) => const Scaffold(body: Text('Settings page'))},
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: OcrSheet(
            ocrState: state,
            lookupState: lookup,
            translationActive: translationActive,
            translationNote: translationNote,
            showHint: showHint,
            onTapCharacter: onTapCharacter ?? (_) {},
            onAddToAnki: onAddToAnki ?? (_) {},
            onAddSentence: onAddSentence ?? () {},
            onDismissTranslationNote: onDismissTranslationNote ?? () {},
            onClose: onClose ?? () {},
          ),
        ),
      ),
    ),
  );
}

/// Sizes the test surface like an iPhone (375 x 812 logical px).
void _phone(WidgetTester tester, {double height = 812}) {
  tester.view.physicalSize = Size(375 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

GlossSpan _word(
  int start,
  String surface, {
  String? ruby,
  String gloss = 'a gloss',
  int extra = 0,
  bool function = false,
}) => GlossSpan(
  start: start,
  length: surface.length,
  surface: surface,
  reading: ruby ?? surface,
  gloss: gloss,
  glossShort: gloss,
  extraSenses: extra,
  isFunctionWord: function,
  baseForm: surface,
  ruby: [RubySegment(surface, ruby)],
);

GlossSpan _plain(int start, String surface) => GlossSpan(
  start: start,
  length: surface.length,
  surface: surface,
  ruby: [RubySegment(surface)],
);

OcrText _text(String line, List<GlossSpan> spans, BgraImage crop) =>
    OcrText(_block, crop, line, gloss: LineGloss(line, spans));

LookupResult _result(String surface, {int start = 0}) => LookupResult(
  start: start,
  length: surface.length,
  surface: surface,
  baseForm: surface,
  matchedReading: 'よみ',
  reasons: const [],
  entry: DictionaryEntry(
    id: 1,
    headword: surface,
    reading: 'よみ',
    senses: const [
      Sense(glosses: ['meaning'], partsOfSpeech: ['n']),
    ],
    isCommon: false,
  ),
  matchedSenseIndexes: const [],
);

LookupState _lookupOf(List<LookupResult> results) =>
    LookupResults(index: 0, results: results, kanji: const {});

/// `魔王を食べた本` through the real glosser over the fake dictionary:
/// 魔王@0 (matched), を@2 (plain), 食べた@3 (matched, inflected), 本@6.
Future<OcrText> _glossed(BgraImage crop) async {
  const line = '魔王を食べた本';
  final gloss = await LineGlosser(FakeDictionary()).gloss(line);
  return OcrText(_block, crop, line, gloss: gloss);
}

Text _textAt(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

Color _underline(WidgetTester tester, String key) {
  final box = tester.widget<DecoratedBox>(find.byKey(Key(key)));
  final border = (box.decoration as BoxDecoration).border! as Border;
  expect(border.bottom.width, 2);
  return border.bottom.color;
}

void main() {
  final crop = testImage(40, 60);
  final wideCrop = testImage(120, 30);

  testWidgets('shows the crop while reading', (tester) async {
    await _pumpSheet(tester, OcrRunning(_block, crop));

    final box = find.byKey(const Key('ocr.crop'));
    expect(box, findsOneWidget);
    expect(tester.getSize(box).height, lessThanOrEqualTo(140));
    expect(
      tester.widget<BgraImageView>(find.byType(BgraImageView)).image,
      crop,
    );
  });

  testWidgets('keeps showing the crop with the text', (tester) async {
    await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

    expect(find.byKey(const Key('ocr.crop')), findsOneWidget);
    expect(find.byKey(const Key('ocr.char.0')), findsOneWidget);
  });

  testWidgets('keeps showing the crop with the failure', (tester) async {
    await _pumpSheet(tester, OcrFailed(_block, crop, 'Could not read'));

    expect(find.byKey(const Key('ocr.crop')), findsOneWidget);
    expect(find.text('Could not read'), findsOneWidget);
  });

  testWidgets('no crop when idle', (tester) async {
    await _pumpSheet(tester, const OcrIdle());

    expect(find.byKey(const Key('ocr.crop')), findsNothing);
  });

  group('the layout (D6e)', () {
    testWidgets('top to bottom: handle, line, translation, words', (
      tester,
    ) async {
      _phone(tester);
      await _pumpSheet(
        tester,
        OcrText(
          _block,
          crop,
          '魔王を',
          translation: 'The demon king.',
          gloss: LineGloss('魔王を', [
            _word(0, '魔王', ruby: 'まおう'),
            _plain(2, 'を'),
          ]),
        ),
        translationActive: true,
      );

      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(top('ocr.handle'), lessThan(top('ocr.char.0')));
      expect(top('ocr.char.0'), lessThan(top('ocr.translation')));
      expect(top('ocr.translation'), lessThan(top('ocr.word.0')));
    });

    testWidgets('a vertical crop is a gutter left of the line, 140 at most', (
      tester,
    ) async {
      _phone(tester);
      await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

      final thumb = tester.getRect(find.byKey(const Key('ocr.crop')));
      expect(thumb.height, lessThanOrEqualTo(140));
      expect(thumb.width, greaterThanOrEqualTo(36));
      final line = tester.getRect(find.byKey(const Key('ocr.char.0')));
      expect(thumb.right, lessThanOrEqualTo(line.left));
    });

    testWidgets('a short block of text keeps the gutter as tall as the text', (
      tester,
    ) async {
      _phone(tester);
      // A real crop is hundreds of pixels tall; that must not set the height.
      await _pumpSheet(
        tester,
        OcrText(_block, testImage(40, 600), '食べる', translation: 'To eat.'),
      );

      final thumb = tester.getRect(find.byKey(const Key('ocr.crop')));
      final line = tester.getRect(find.byType(RubyLine));
      final translation = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('ocr.translation')),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(thumb.height, lessThan(140));
      expect(thumb.height, closeTo(translation.bottom - line.top, 1));
    });

    testWidgets('a tall block of text lets the gutter grow to 140', (
      tester,
    ) async {
      _phone(tester);
      // 40 characters wrap to several rows at 375 px.
      final line = '魔王' * 20;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, line, translation: 'x' * 80),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('ocr.crop'))).height, 140);
    });

    testWidgets('a horizontal crop is full width and 72 high at most', (
      tester,
    ) async {
      _phone(tester);
      await _pumpSheet(tester, OcrText(_block, wideCrop, '食べる'));

      final thumb = tester.getRect(find.byKey(const Key('ocr.crop')));
      final sheet = tester.getRect(find.byKey(const Key('ocr.sheet')));
      expect(thumb.width, sheet.width - 32);
      expect(thumb.height, lessThanOrEqualTo(72));
      expect(
        thumb.bottom,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('ocr.char.0'))).dy,
        ),
        reason: 'the line comes under the picture',
      );
    });

    testWidgets('tapping the crop opens it zoomable, the X closes it', (
      tester,
    ) async {
      await _pumpSheet(tester, OcrText(_block, crop, '食べる'));
      expect(find.byKey(const Key('ocr.crop.zoom')), findsNothing);

      await tester.tap(find.byKey(const Key('ocr.crop')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ocr.crop.zoom')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byKey(const Key('ocr.crop.zoom.close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr.crop.zoom')), findsNothing);
    });

    testWidgets('tapping outside the zoomed crop closes it', (tester) async {
      await _pumpSheet(tester, OcrText(_block, crop, '食べる'));
      await tester.tap(find.byKey(const Key('ocr.crop')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ocr.crop.zoom')), findsNothing);
    });

    testWidgets(
      'the bar is inside the sheet at 600 px, Add word needs a result',
      (tester) async {
        _phone(tester, height: 600);
        final line = OcrText(
          _block,
          crop,
          '魔王',
          gloss: LineGloss('魔王', [_word(0, '魔王', ruby: 'まおう')]),
        );
        await _pumpSheet(tester, line);

        expect(find.byKey(const Key('anki.addWord')), findsNothing);
        await _pumpSheet(tester, line, lookup: _lookupOf([_result('魔王')]));

        final sheet = tester.getRect(find.byKey(const Key('ocr.sheet')));
        expect(sheet.height, lessThanOrEqualTo(600 * 0.6 + 0.5));
        for (final key in ['anki.addSentence', 'anki.addWord']) {
          final r = tester.getRect(find.byKey(Key(key)));
          expect(r.bottom, lessThanOrEqualTo(sheet.bottom), reason: key);
          expect(r.top, greaterThanOrEqualTo(sheet.top), reason: key);
        }
        expect(find.text('Add 魔王'), findsOneWidget);
      },
    );

    testWidgets('no Add word for an empty lookup or while loading', (
      tester,
    ) async {
      final line = OcrText(_block, crop, '魔王');
      for (final lookup in [
        const LookupLoading(0),
        _lookupOf(const []),
        const LookupIdle(),
      ]) {
        await _pumpSheet(tester, line, lookup: lookup);

        expect(find.byKey(const Key('anki.addWord')), findsNothing);
      }
    });

    testWidgets('Add word hands the longest result to Anki', (tester) async {
      final handed = <LookupResult>[];
      final results = [_result('魔王'), _result('魔')];
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '魔王'),
        lookup: _lookupOf(results),
        onAddToAnki: handed.add,
      );

      await tester.tap(find.byKey(const Key('anki.addWord')));

      expect(handed, [results.first]);
    });

    testWidgets('a short fling down on the handle closes the sheet', (
      tester,
    ) async {
      var closed = 0;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        onClose: () => closed++,
      );

      await tester.fling(
        find.byKey(const Key('ocr.handle')),
        const Offset(0, 50),
        1500,
      );

      expect(closed, 1);
    });

    testWidgets('a slow drag of more than 80 px closes it too', (tester) async {
      var closed = 0;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        onClose: () => closed++,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('ocr.handle'))),
      );
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();

      expect(closed, 1);
    });

    testWidgets('a short slow drag does not', (tester) async {
      var closed = 0;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        onClose: () => closed++,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('ocr.handle'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();

      expect(closed, 0);
    });

    testWidgets('scrolling the list is not a swipe to close', (tester) async {
      _phone(tester, height: 400);
      var closed = 0;
      final gloss = LineGloss('魔王' * 3, [
        for (var i = 0; i < 3; i++) _word(i * 2, '魔王', ruby: 'まおう'),
      ]);
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '魔王' * 3, gloss: gloss),
        lookup: _lookupOf([_result('魔王')]),
        onClose: () => closed++,
      );

      await tester.fling(find.byType(ListView), const Offset(0, -300), 2000);
      await tester.fling(find.byType(ListView), const Offset(0, 300), 2000);

      expect(closed, 0);
    });

    testWidgets('the close button is a 44 pt target', (tester) async {
      await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

      expect(
        tester.getSize(find.byKey(const Key('ocr.close'))),
        const Size(44, 44),
      );
    });

    testWidgets('the crop is announced as a button, in both layouts', (
      tester,
    ) async {
      for (final image in [crop, wideCrop]) {
        await _pumpSheet(tester, OcrText(_block, image, '食べる'));

        expect(find.bySemanticsLabel('Bubble photo, enlarge'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Bubble photo, enlarge')),
          matchesSemantics(
            label: 'Bubble photo, enlarge',
            isButton: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      }
    });

    testWidgets('the close button closes', (tester) async {
      var closed = 0;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        onClose: () => closed++,
      );

      await tester.tap(find.byKey(const Key('ocr.close')));

      expect(closed, 1);
    });

    testWidgets('the hint shows only while it is wanted', (tester) async {
      await _pumpSheet(tester, OcrText(_block, crop, '食べる'), showHint: true);
      expect(find.text('Tap a character to look it up.'), findsOneWidget);

      await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

      expect(find.text('Tap a character to look it up.'), findsNothing);
    });

    testWidgets(
      'the line, its translation and four words fit a phone without scrolling',
      (tester) async {
        _phone(tester);
        const line = '魔王を倒した勇者';
        final gloss = LineGloss(line, [
          _word(0, '魔王', ruby: 'まおう', gloss: 'Satan · demon lord'),
          _plain(2, 'を'),
          _word(3, '倒した', ruby: 'たおした', gloss: 'to throw down'),
          _word(6, '勇者', ruby: 'ゆうしゃ', gloss: 'hero'),
          _word(8, '達', gloss: 'plural suffix'),
        ]);
        await _pumpSheet(
          tester,
          OcrText(
            _block,
            crop,
            line,
            gloss: gloss,
            translation: 'The hero who defeated the Demon King.',
          ),
          translationActive: true,
          showHint: true,
        );

        final sheet = tester.getRect(find.byKey(const Key('ocr.sheet')));
        final bar = tester.getRect(find.byKey(const Key('anki.addSentence')));
        final tops = {
          for (var i = 0; i < line.length; i++)
            tester.getTopLeft(find.byKey(Key('ocr.char.$i'))).dy,
        };
        expect(tops, hasLength(1), reason: 'one row of Japanese');
        for (final start in [0, 3, 6, 8]) {
          final row = tester.getRect(find.byKey(Key('ocr.word.$start')));
          expect(row.height, 44);
          expect(row.bottom, lessThanOrEqualTo(bar.top), reason: '$start');
          expect(row.top, greaterThanOrEqualTo(sheet.top));
        }
      },
    );
  });

  group('the translation line (D6c, D6e.3)', () {
    testWidgets('a translation shows under the line, muted, with an icon', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる', translation: 'To eat.'),
        translationActive: true,
      );

      expect(_textAt(tester, 'ocr.translation').data, 'To eat.');
      expect(find.byKey(const Key('ocr.translation.pending')), findsNothing);
      expect(find.byIcon(Icons.translate), findsOneWidget);
      final style = _textAt(tester, 'ocr.translation').style!;
      final scheme = Theme.of(
        tester.element(find.byKey(const Key('ocr.sheet'))),
      ).colorScheme;
      expect(style.color, scheme.onSurfaceVariant);
      expect(style.fontStyle, isNot(FontStyle.italic));
      final line = tester.getBottomLeft(find.byKey(const Key('ocr.char.0'))).dy;
      expect(
        tester.getTopLeft(find.byKey(const Key('ocr.translation'))).dy,
        greaterThanOrEqualTo(line),
      );
    });

    testWidgets(
      'a translation shows even if the sheet was not told it is active',
      (tester) async {
        await _pumpSheet(
          tester,
          OcrText(_block, crop, '食べる', translation: 'To eat.'),
        );

        expect(find.byKey(const Key('ocr.translation')), findsOneWidget);
      },
    );

    testWidgets('while it is pending a skeleton bar stands in, with no text', (
      tester,
    ) async {
      _phone(tester);
      await _pumpSheet(
        tester,
        OcrText(_block, wideCrop, '食べる'),
        translationActive: true,
      );

      final bar = find.byKey(const Key('ocr.translation.pending'));
      expect(bar, findsOneWidget);
      expect(
        find.descendant(of: bar, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.text('Translating…'), findsNothing);
      expect(tester.getSize(bar).height, 16);
      final list = tester.getSize(find.byType(ListView)).width - 32;
      expect(tester.getSize(bar).width, closeTo(list * 0.6, 1));
      final decoration =
          tester.widget<Container>(bar).decoration! as BoxDecoration;
      final scheme = Theme.of(
        tester.element(find.byKey(const Key('ocr.sheet'))),
      ).colorScheme;
      expect(decoration.color, scheme.surfaceContainerHighest);
      expect(find.byKey(const Key('ocr.translation')), findsNothing);
    });

    testWidgets('the skeleton and the line take the same height', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        OcrText(_block, wideCrop, '食べる'),
        translationActive: true,
      );
      final pending = tester.getSize(find.byType(ListView)).height;

      await _pumpSheet(
        tester,
        OcrText(_block, wideCrop, '食べる', translation: 'To eat.'),
        translationActive: true,
      );

      expect(tester.getSize(find.byType(ListView)).height, pending);
    });

    testWidgets('nothing shows when translation is not active', (tester) async {
      await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

      expect(find.byKey(const Key('ocr.translation')), findsNothing);
      expect(find.byKey(const Key('ocr.translation.pending')), findsNothing);
    });

    testWidgets(
      'an empty translation shows nothing, not even the pending line',
      (tester) async {
        await _pumpSheet(
          tester,
          OcrText(_block, crop, '食べる', translation: ''),
          translationActive: true,
        );

        expect(find.byKey(const Key('ocr.translation')), findsNothing);
        expect(find.byKey(const Key('ocr.translation.pending')), findsNothing);
      },
    );

    testWidgets('no line while reading or after a failed read', (tester) async {
      for (final state in [
        OcrRunning(_block, crop),
        OcrFailed(_block, crop, 'x'),
      ]) {
        await _pumpSheet(tester, state, translationActive: true);

        expect(find.byKey(const Key('ocr.translation')), findsNothing);
        expect(find.byKey(const Key('ocr.translation.pending')), findsNothing);
      }
    });

    testWidgets(
      'the note is a muted line of at most two, and no note means no line',
      (tester) async {
        await _pumpSheet(tester, OcrText(_block, crop, '食べる'));
        expect(find.byKey(const Key('ocr.translation.note')), findsNothing);

        await _pumpSheet(
          tester,
          OcrText(_block, crop, '食べる'),
          translationNote: 'This phone cannot translate Japanese.',
        );

        final note = _textAt(tester, 'ocr.translation.note');
        expect(note.data, 'This phone cannot translate Japanese.');
        expect(note.maxLines, 2);
        expect(find.text('Settings'), findsOneWidget);
      },
    );

    testWidgets('beside a vertical crop the note still gets the full width', (
      tester,
    ) async {
      _phone(tester);
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        translationNote: 'Japanese or English is not downloaded yet.',
      );

      final note = tester.getRect(
        find.byKey(const Key('ocr.translation.note')),
      );
      final thumb = tester.getRect(find.byKey(const Key('ocr.crop')));
      expect(note.left, 16, reason: 'under the gutter, not beside it');
      expect(note.top, greaterThanOrEqualTo(thumb.bottom));
    });

    testWidgets('the note\'s Settings button opens Settings and dismisses it', (
      tester,
    ) async {
      var dismissed = 0;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        translationNote: 'Translation failed for this bubble.',
        onDismissTranslationNote: () => dismissed++,
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(dismissed, 1);
      expect(find.text('Settings page'), findsOneWidget);
    });

    testWidgets('closing the sheet dismisses the note', (tester) async {
      var dismissed = 0;
      var closed = 0;
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        translationNote: 'Translation failed for this bubble.',
        onDismissTranslationNote: () => dismissed++,
        onClose: () => closed++,
      );

      await tester.tap(find.byKey(const Key('ocr.close')));

      expect((dismissed, closed), (1, 1));
    });
  });

  group('the sentence layer (D6b, D6e)', () {
    testWidgets(
      'until the gloss arrives the line is plain cells and the button is off',
      (tester) async {
        await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

        for (final i in [0, 1, 2]) {
          expect(find.byKey(Key('ocr.char.$i')), findsOneWidget);
        }
        expect(find.byKey(const Key('ocr.ruby.0')), findsNothing);
        expect(find.byKey(const Key('ocr.word.0')), findsNothing);
        expect(find.byKey(const Key('ocr.span.0')), findsNothing);
        final button = tester.widget<ButtonStyleButton>(
          find.byKey(const Key('anki.addSentence')),
        );
        expect(button.onPressed, isNull);
        expect(find.text('Add sentence'), findsOneWidget);
      },
    );

    testWidgets('the button is off for a line with no recognised word', (
      tester,
    ) async {
      final gloss = await LineGlosser(FakeDictionary()).gloss('。！');
      await _pumpSheet(tester, OcrText(_block, crop, '。！', gloss: gloss));

      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('anki.addSentence')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the button is off while reading and when the read failed', (
      tester,
    ) async {
      for (final state in [
        OcrRunning(_block, crop),
        OcrFailed(_block, crop, 'x'),
      ]) {
        await _pumpSheet(tester, state);

        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const Key('anki.addSentence')),
              )
              .onPressed,
          isNull,
        );
      }
    });

    testWidgets('readings sit over the kanji runs, words get one row each', (
      tester,
    ) async {
      await _pumpSheet(tester, await _glossed(crop));

      expect(_textAt(tester, 'ocr.ruby.0').data, 'まおう');
      expect(_textAt(tester, 'ocr.ruby.3').data, 'た');
      expect(
        find.byKey(const Key('ocr.ruby.4')),
        findsNothing,
        reason: 'okurigana べ has no reading',
      );
      expect(find.byKey(const Key('ocr.ruby.2')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('ocr.word.0')),
          matching: find.text('devil king'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ocr.word.3')),
          matching: find.text('to eat'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ocr.word.6')),
          matching: find.text('book'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ocr.word.2')), findsNothing);
      for (final i in [0, 1, 2, 3, 4, 5, 6]) {
        expect(find.byKey(Key('ocr.char.$i')), findsOneWidget);
      }
    });

    testWidgets('ruby is small text over the characters it reads', (
      tester,
    ) async {
      await _pumpSheet(tester, await _glossed(crop));

      final ruby = tester.getRect(find.byKey(const Key('ocr.ruby.3')));
      final kanji = tester.getRect(find.byKey(const Key('ocr.char.3')));
      expect(ruby.bottom, lessThanOrEqualTo(kanji.top + 1));
      expect(
        _textAt(tester, 'ocr.ruby.3').style!.fontSize!,
        lessThan(
          Theme.of(tester.element(find.byKey(const Key('ocr.sheet'))))
              .textTheme
              .headlineSmall!
              .fontSize!,
        ),
      );
    });

    testWidgets(
      'matched words are underlined in alternating colours, plain text is not',
      (tester) async {
        await _pumpSheet(tester, await _glossed(crop));
        final scheme = Theme.of(
          tester.element(find.byKey(const Key('ocr.sheet'))),
        ).colorScheme;

        expect(_underline(tester, 'ocr.span.0'), scheme.primary);
        expect(_underline(tester, 'ocr.span.3'), scheme.tertiary);
        expect(_underline(tester, 'ocr.span.6'), scheme.primary);
        expect(find.byKey(const Key('ocr.span.2')), findsNothing);
      },
    );

    testWidgets('a function word keeps its underline but has no row', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        _text('魔王を', [
          _word(0, '魔王', ruby: 'まおう'),
          _word(2, 'を', function: true),
        ], crop),
      );

      expect(find.byKey(const Key('ocr.span.2')), findsOneWidget);
      expect(find.byKey(const Key('ocr.word.2')), findsNothing);
      expect(find.byKey(const Key('ocr.word.0')), findsOneWidget);
    });

    testWidgets(
      'tapping a word row looks the word up from its first character',
      (tester) async {
        final taps = <int>[];
        await _pumpSheet(
          tester,
          await _glossed(crop),
          onTapCharacter: taps.add,
        );

        await tester.tap(find.byKey(const Key('ocr.word.3')));
        await tester.tap(find.byKey(const Key('ocr.word.0')));

        expect(taps, [3, 0]);
      },
    );

    testWidgets(
      'several matched words wrap to a second row on a 375 px phone',
      (tester) async {
        _phone(tester);
        const line = '魔王食べた本魔王食べた本魔王食べた本';
        final gloss = await LineGlosser(FakeDictionary()).gloss(line);
        await _pumpSheet(tester, OcrText(_block, crop, line, gloss: gloss));

        expect(tester.takeException(), isNull);
        for (var i = 0; i < line.length; i++) {
          expect(find.byKey(Key('ocr.char.$i')), findsOneWidget);
        }
        final first = tester.getTopLeft(find.byKey(const Key('ocr.char.0')));
        final last = tester.getTopLeft(
          find.byKey(Key('ocr.char.${line.length - 1}')),
        );
        expect(last.dy, greaterThan(first.dy + 52), reason: 'a second row');
      },
    );

    testWidgets('a word wider than the sheet does not overflow', (
      tester,
    ) async {
      _phone(tester);
      final line = 'あ' * 40;
      await _pumpSheet(
        tester,
        _text(line, [_word(0, line, gloss: 'long ' * 30)], crop),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'tapping a character inside a matched word reports that character',
      (tester) async {
        final taps = <int>[];
        await _pumpSheet(
          tester,
          await _glossed(crop),
          onTapCharacter: taps.add,
        );

        await tester.tap(find.byKey(const Key('ocr.char.4')));
        await tester.tap(find.byKey(const Key('ocr.char.2')));
        await tester.tap(find.byKey(const Key('ocr.char.1')));

        expect(taps, [4, 2, 1]);
      },
    );

    testWidgets('the add-sentence button calls back once the gloss is there', (
      tester,
    ) async {
      var calls = 0;
      await _pumpSheet(
        tester,
        await _glossed(crop),
        onAddSentence: () => calls++,
      );

      await tester.tap(find.byKey(const Key('anki.addSentence')));

      expect(calls, 1);
    });
  });

  group('the card shows the reading of the form that matched (D6b.2)', () {
    const beerEntry = DictionaryEntry(
      id: 1104550,
      headword: '麦酒',
      reading: 'ばくしゅ',
      senses: [
        Sense(glosses: ['beer'], partsOfSpeech: ['n']),
      ],
      isCommon: false,
    );
    LookupState lookupFor(String reading) => LookupResults(
      index: 0,
      kanji: const {},
      results: [
        LookupResult(
          start: 0,
          length: 4,
          surface: 'ビール',
          baseForm: 'ビール',
          matchedReading: reading,
          reasons: const [],
          entry: beerEntry,
          matchedSenseIndexes: const [],
        ),
      ],
    );

    testWidgets('a kana spelling reads as itself, the entry headword follows', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        OcrText(_block, crop, 'ビール'),
        lookup: lookupFor('ビール'),
      );

      // The line is one cell per character, so this is the card's word.
      expect(find.text('ビール'), findsOneWidget);
      expect(find.byKey(const Key('lookup.matched.0')), findsOneWidget);
      expect(find.text('麦酒【ばくしゅ】'), findsOneWidget);
      expect(find.text('ばくしゅ'), findsNothing);
    });

    testWidgets(
      'when the matched form reads as the entry does, the card is as before',
      (tester) async {
        await _pumpSheet(
          tester,
          OcrText(_block, crop, '麦酒'),
          lookup: lookupFor('ばくしゅ'),
        );

        expect(find.text('麦酒'), findsOneWidget);
        expect(find.text('ばくしゅ'), findsOneWidget);
        expect(find.byKey(const Key('lookup.matched.0')), findsNothing);
        expect(find.textContaining('【'), findsNothing);
      },
    );
  });
}
