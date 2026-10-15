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
import 'package:yomitanuki/ui/reader/view_model/reader_state.dart';

import '../../../fakes/fake_dictionary.dart';
import '../../../fakes/images.dart';

const _block = TextBlock(box: Rect.fromLTWH(10, 10, 20, 20), confidence: 0.9);

Future<void> _pumpSheet(
  WidgetTester tester,
  OcrState state, {
  LookupState lookup = const LookupIdle(),
  void Function(int index)? onTapCharacter,
  VoidCallback? onAddSentence,
  bool translationActive = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: OcrSheet(
            ocrState: state,
            lookupState: lookup,
            translationActive: translationActive,
            onTapCharacter: onTapCharacter ?? (_) {},
            onAddToAnki: (_) {},
            onAddSentence: onAddSentence ?? () {},
            onClose: () {},
          ),
        ),
      ),
    ),
  );
}

/// `魔王を食べた本` through the real glosser over the fake dictionary:
/// 魔王@0 (matched), を@2 (plain), 食べた@3 (matched, inflected), 本@6.
Future<OcrText> _glossed(BgraImage crop) async {
  const line = '魔王を食べた本';
  final gloss = await LineGlosser(FakeDictionary()).gloss(line);
  return OcrText(_block, crop, line, gloss: gloss);
}

Text _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

Color _underline(WidgetTester tester, String key) {
  final box = tester.widget<DecoratedBox>(find.byKey(Key(key)));
  final border = (box.decoration as BoxDecoration).border! as Border;
  expect(border.bottom.width, 2);
  return border.bottom.color;
}

void main() {
  final crop = testImage(40, 60);

  testWidgets('shows the crop in a 96 px box while reading', (tester) async {
    await _pumpSheet(tester, OcrRunning(_block, crop));

    final box = find.byKey(const Key('ocr.crop'));
    expect(box, findsOneWidget);
    expect(tester.getSize(box).height, 96);
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
  group('the translation line (D6c)', () {
    testWidgets('a translation shows between the crop and the text', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる', translation: 'To eat.'),
        translationActive: true,
      );

      expect(_text(tester, 'ocr.translation').data, 'To eat.');
      expect(find.byKey(const Key('ocr.translation.pending')), findsNothing);
      final cropBottom = tester
          .getBottomLeft(find.byKey(const Key('ocr.crop')))
          .dy;
      final line = tester
          .getTopLeft(find.byKey(const Key('ocr.translation')))
          .dy;
      final cells = tester.getTopLeft(find.byKey(const Key('ocr.char.0'))).dy;
      expect(cropBottom, lessThanOrEqualTo(line));
      expect(line, lessThan(cells));
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

    testWidgets('while it is pending the sheet says so', (tester) async {
      await _pumpSheet(
        tester,
        OcrText(_block, crop, '食べる'),
        translationActive: true,
      );

      expect(find.text('Translating…'), findsOneWidget);
      expect(find.byKey(const Key('ocr.translation')), findsNothing);
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
  });

  group('the sentence layer (D6b)', () {
    testWidgets(
      'until the gloss arrives the line is plain cells and the button is off',
      (tester) async {
        await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

        for (final i in [0, 1, 2]) {
          expect(find.byKey(Key('ocr.char.$i')), findsOneWidget);
        }
        expect(find.byKey(const Key('ocr.ruby.0')), findsNothing);
        expect(find.byKey(const Key('ocr.gloss.0')), findsNothing);
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

    testWidgets(
      'readings sit over the kanji runs, glosses under the matched words',
      (tester) async {
        await _pumpSheet(tester, await _glossed(crop));

        expect(_text(tester, 'ocr.ruby.0').data, 'まおう');
        expect(_text(tester, 'ocr.ruby.3').data, 'た');
        expect(
          find.byKey(const Key('ocr.ruby.4')),
          findsNothing,
          reason: 'okurigana べ has no reading',
        );
        expect(find.byKey(const Key('ocr.ruby.2')), findsNothing);
        expect(_text(tester, 'ocr.gloss.0').data, 'devil king, demon lord');
        expect(_text(tester, 'ocr.gloss.3').data, 'to eat');
        expect(_text(tester, 'ocr.gloss.6').data, 'book, volume');
        expect(find.byKey(const Key('ocr.gloss.2')), findsNothing);
        for (final i in [0, 1, 2, 3, 4, 5, 6]) {
          expect(find.byKey(Key('ocr.char.$i')), findsOneWidget);
        }
      },
    );

    testWidgets('ruby is small text over the characters it reads', (
      tester,
    ) async {
      await _pumpSheet(tester, await _glossed(crop));

      final ruby = tester.getRect(find.byKey(const Key('ocr.ruby.3')));
      final kanji = tester.getRect(find.byKey(const Key('ocr.char.3')));
      expect(ruby.bottom, lessThanOrEqualTo(kanji.top + 1));
      expect(
        _text(tester, 'ocr.ruby.3').style!.fontSize!,
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

    testWidgets('a long gloss is at most two lines and 160 px wide', (
      tester,
    ) async {
      const line = '魔王';
      final gloss = LineGloss(line, [
        GlossSpan(
          start: 0,
          length: 2,
          surface: line,
          reading: 'まおう',
          gloss: List.filled(30, 'demon lord').join(', '),
          baseForm: line,
          ruby: const [RubySegment(line, 'まおう')],
        ),
      ]);
      await _pumpSheet(tester, OcrText(_block, crop, line, gloss: gloss));

      final text = _text(tester, 'ocr.gloss.0');
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(find.byKey(const Key('ocr.gloss.0'))).width,
        lessThanOrEqualTo(160),
      );
    });

    testWidgets(
      'several matched words wrap to a second row on a 375 px phone',
      (tester) async {
        tester.view.physicalSize = const Size(375, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const line = '魔王食べた本魔王食べた本';
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
        expect(last.dy, greaterThan(first.dy + 44), reason: 'a second row');
      },
    );

    testWidgets(
      'a word wider than the sheet scales down instead of overflowing',
      (tester) async {
        final line = 'あ' * 40;
        final gloss = LineGloss(line, [
          GlossSpan(
            start: 0,
            length: 40,
            surface: line,
            reading: line,
            gloss: 'long',
            baseForm: line,
            ruby: [RubySegment(line)],
          ),
        ]);
        await _pumpSheet(tester, OcrText(_block, crop, line, gloss: gloss));

        expect(tester.takeException(), isNull);
        final sheet = tester.getSize(find.byKey(const Key('ocr.sheet')));
        expect(
          tester.getSize(find.byKey(const Key('ocr.span.0'))).width,
          lessThanOrEqualTo(sheet.width),
        );
      },
    );

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
