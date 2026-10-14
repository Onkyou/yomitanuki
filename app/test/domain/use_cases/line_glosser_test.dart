import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/use_cases/line_glosser.dart';

import '../../fakes/fake_dictionary.dart';

void main() {
  late FakeDictionary dictionary;
  late LineGlosser glosser;

  setUp(() {
    dictionary = FakeDictionary();
    glosser = LineGlosser(dictionary);
  });

  /// `start+length` and surface of every span, matched ones marked.
  List<String> shape(LineGloss gloss) => [
    for (final s in gloss.spans)
      '${s.matched ? '*' : ''}${s.surface}@${s.start}+${s.length}',
  ];

  test('魔王を倒した: one matched word, the rest one plain span', () async {
    final gloss = await glosser.gloss('魔王を倒した');

    // The fake has no 倒す, so を倒した is not a word; plain neighbours merge.
    expect(shape(gloss), ['*魔王@0+2', 'を倒した@2+4']);
    final word = gloss.spans.first;
    expect(word.reading, 'まおう');
    expect(word.baseForm, '魔王');
    expect(word.gloss, 'devil king, demon lord');
    expect(word.ruby, const [RubySegment('魔王', 'まおう')]);
    final plain = gloss.spans.last;
    expect(plain.reading, isNull);
    expect(plain.gloss, isNull);
    expect(plain.baseForm, isNull);
    expect(plain.ruby, const [RubySegment('を倒した')]);
    expect(gloss.line, '魔王を倒した');
  });

  test(
    'walks the line: each lookup starts where the last match ended',
    () async {
      await glosser.gloss('魔王を本');

      expect(dictionary.lookups, [('魔王を本', 0), ('魔王を本', 2), ('魔王を本', 3)]);
    },
  );

  test(
    'an inflected word keeps its surface, with the base form\'s reading',
    () async {
      final gloss = await glosser.gloss('食べた本');

      expect(shape(gloss), ['*食べた@0+3', '*本@3+1']);
      final eaten = gloss.spans.first;
      expect(eaten.baseForm, '食べる');
      expect(eaten.reading, 'たべる');
      expect(eaten.gloss, 'to eat');
      expect(eaten.ruby, const [RubySegment('食', 'た'), RubySegment('べた')]);
    },
  );

  test(
    'the reading line reads inflected words as written, not as the base',
    () async {
      final gloss = await glosser.gloss('魔王が食べた。');

      expect(gloss.readingLine, 'まおうがたべた。');
    },
  );

  test('a katakana word stays katakana in the reading line', () async {
    dictionary.onLookup = (text, index) => index == 0
        ? [
            const LookupResult(
              start: 0,
              length: 3,
              surface: 'ビール',
              baseForm: 'ビール',
              matchedReading: 'ビール',
              reasons: [],
              entry: taberuEntry,
            ),
          ]
        : [];

    final gloss = await glosser.gloss('ビールを');

    expect(gloss.spans.first.ruby, const [RubySegment('ビール')]);
    expect(gloss.readingLine, 'ビールを');
  });

  test('the gloss line is surface: gloss for each matched span', () async {
    final gloss = await glosser.gloss('魔王を食べた本');

    expect(
      gloss.glossLine,
      '魔王: devil king, demon lord\n食べた: to eat\n本: book, volume',
    );
  });

  test('only the first sense is used, joined with commas', () async {
    final gloss = await glosser.gloss('本');

    expect(gloss.spans.single.gloss, 'book, volume');
  });

  test(
    'a line of punctuation and spaces has no matched span and no lookups',
    () async {
      const line = '。！　 …、';
      final gloss = await glosser.gloss(line);

      expect(gloss.spans.where((s) => s.matched), isEmpty);
      expect(shape(gloss), ['$line@0+${line.length}']);
      expect(gloss.readingLine, line);
      expect(gloss.glossLine, '');
      expect(dictionary.lookups, isEmpty);
    },
  );

  test(
    'punctuation between words is plain text that stays in the line',
    () async {
      final gloss = await glosser.gloss('魔王、本');

      expect(shape(gloss), ['*魔王@0+2', '、@2+1', '*本@3+1']);
      expect(gloss.readingLine, 'まおう、ほん');
      expect(dictionary.lookups.map((l) => l.$2), [0, 3]);
    },
  );

  test('an astral-plane character is one code point of plain text', () async {
    final gloss = await glosser.gloss('𠮷本');

    expect(shape(gloss), ['𠮷@0+2', '*本@2+1']);
    expect(dictionary.lookups.map((l) => l.$2), [0, 2]);
  });

  test('an empty line has no spans', () async {
    final gloss = await glosser.gloss('');

    expect(gloss.spans, isEmpty);
    expect(gloss.readingLine, '');
  });

  test('a match that claims no length cannot stall the walk', () async {
    dictionary.results = [
      const LookupResult(
        start: 0,
        length: 0,
        surface: '',
        baseForm: '',
        matchedReading: '',
        reasons: [],
        entry: taberuEntry,
      ),
    ];

    final gloss = await glosser.gloss('ab');

    expect(shape(gloss), ['ab@0+2']);
  });

  test(
    'a result that does not sit at the offset it was asked for is no match',
    () async {
      LookupResult result(int start, String surface) => LookupResult(
        start: start,
        length: surface.length,
        surface: surface,
        baseForm: surface,
        matchedReading: 'ほん',
        reasons: const [],
        entry: taberuEntry,
      );
      // A wrong start, then a surface that is not the text at that offset.
      dictionary.onLookup = (text, index) => [result(index + 1, '王')];
      expect(shape(await glosser.gloss('魔王')), ['魔王@0+2']);
      dictionary.onLookup = (text, index) => [result(index, '本')];

      final gloss = await glosser.gloss('魔王');

      expect(shape(gloss), ['魔王@0+2']);
      expect(gloss.spans.single.matched, isFalse);
      expect(gloss.line, gloss.spans.map((s) => s.surface).join());
    },
  );

  test('a dictionary error propagates to the caller', () async {
    dictionary.error = StateError('database closed');

    await expectLater(glosser.gloss('魔王'), throwsStateError);
  });
}
