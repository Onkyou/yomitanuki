import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
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
              matchedSenseIndexes: [],
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
        matchedSenseIndexes: [],
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
        matchedSenseIndexes: const [],
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

  group('the short gloss (D6e.2)', () {
    LookupResult result(
      DictionaryEntry entry, {
      List<int> matched = const [],
      String surface = '本',
    }) => LookupResult(
      start: 0,
      length: surface.length,
      surface: surface,
      baseForm: surface,
      matchedReading: 'ほん',
      reasons: const [],
      entry: entry,
      matchedSenseIndexes: matched,
    );

    DictionaryEntry entry(List<Sense> senses) => DictionaryEntry(
      id: 1,
      headword: '本',
      reading: 'ほん',
      senses: senses,
      isCommon: false,
    );

    Sense sense(String gloss, [List<String> pos = const ['n']]) =>
        Sense(glosses: [gloss, 'second $gloss'], partsOfSpeech: pos);

    Future<GlossSpan> glossOf(LookupResult r) async {
      dictionary.onLookup = (text, index) => index == 0 ? [r] : [];
      return (await glosser.gloss(r.surface)).spans.single;
    }

    test('an exact match shows sense 1 only, and the long gloss is unchanged', () async {
      final span = await glossOf(result(taberuEntry, surface: '食べる'));

      expect(span.glossShort, 'to eat');
      expect(span.gloss, 'to eat');
      // The entry's second sense applies too, so the reader is told it exists.
      expect(span.extraSenses, 1);
    });

    test('an entry with one sense has nothing extra', () async {
      final span = (await glosser.gloss('本')).spans.single;

      expect(span.glossShort, 'book');
      expect(span.extraSenses, 0);
    });

    test('matched senses come first, up to two, joined with a dot', () async {
      final e = entry([
        sense('one'),
        sense('two'),
        sense('three'),
        sense('four'),
      ]);

      final span = await glossOf(result(e, matched: [2, 1, 3]));

      expect(span.glossShort, 'three · two');
      expect(span.extraSenses, 1);
    });

    test('食べた with matched sense 1 uses that sense, not sense 0', () async {
      final span = await glossOf(
        result(taberuEntry, matched: [1], surface: '食べた'),
      );

      expect(span.glossShort, 'to live on (e.g. a salary)');
      expect(span.extraSenses, 0);
    });

    test(
      'a join over 32 characters drops whole glosses from the end',
      () async {
        final e = entry([sense('a' * 20), sense('b' * 20)]);

        final span = await glossOf(result(e, matched: [0, 1]));

        expect(span.glossShort, 'a' * 20);
        expect(span.extraSenses, 1);
      },
    );

    test('a join of exactly 32 characters stays whole', () async {
      final e = entry([sense('a' * 15), sense('b' * 14)]);

      final span = await glossOf(result(e, matched: [0, 1]));

      expect(span.glossShort, '${'a' * 15} · ${'b' * 14}');
      expect(span.extraSenses, 0);
    });

    test('a single gloss longer than 32 characters stays whole', () async {
      final e = entry([sense('c' * 50), sense('d')]);

      final span = await glossOf(result(e, matched: [0, 1]));

      expect(span.glossShort, 'c' * 50);
      expect(span.extraSenses, 1);
    });

    test('indexes outside the entry are ignored', () async {
      final span = await glossOf(
        result(taberuEntry, matched: [7, 1], surface: '食べた'),
      );

      expect(span.glossShort, 'to live on (e.g. a salary)');
    });

    test('an unmatched span has no short gloss', () async {
      final span = (await glosser.gloss('を')).spans.single;

      expect(span.glossShort, isNull);
      expect(span.extraSenses, 0);
      expect(span.isFunctionWord, isFalse);
    });
  });

  group('function words (D6e.1)', () {
    Future<GlossSpan> spanFor(
      List<Sense> senses, {
      List<int> matched = const [],
    }) async {
      final e = DictionaryEntry(
        id: 2,
        headword: 'を',
        reading: 'を',
        senses: senses,
        isCommon: true,
      );
      dictionary.onLookup = (text, index) => [
        LookupResult(
          start: 0,
          length: 1,
          surface: 'を',
          baseForm: 'を',
          matchedReading: 'を',
          reasons: const [],
          entry: e,
          matchedSenseIndexes: matched,
        ),
      ];
      return (await glosser.gloss('を')).spans.single;
    }

    Sense pos(List<String> tags) =>
        Sense(glosses: const ['x'], partsOfSpeech: tags);

    test('a particle is a function word', () async {
      expect(
        (await spanFor([
          pos(['prt']),
        ])).isFunctionWord,
        isTrue,
      );
    });

    for (final tag in ['aux', 'aux-v', 'aux-adj', 'cop', 'cop-da']) {
      test('$tag is a function word', () async {
        expect(
          (await spanFor([
            pos([tag]),
          ])).isFunctionWord,
          isTrue,
        );
      });
    }

    test('a conjunction is not: そして and しかし deserve a gloss', () async {
      expect(
        (await spanFor([
          pos(['conj']),
        ])).isFunctionWord,
        isFalse,
      );
    });

    test('a noun is not', () async {
      expect(
        (await spanFor([
          pos(['n']),
        ])).isFunctionWord,
        isFalse,
      );
    });

    test('one content tag among function tags is not', () async {
      expect(
        (await spanFor([
          pos(['prt', 'n']),
        ])).isFunctionWord,
        isFalse,
      );
    });

    test('only the considered senses decide', () async {
      final senses = [
        pos(['n']),
        pos(['prt']),
      ];

      // Exact match considers sense 1 (a noun); the matched sense is the particle.
      expect((await spanFor(senses)).isFunctionWord, isFalse);
      expect((await spanFor(senses, matched: [1])).isFunctionWord, isTrue);
    });

    test('a sense with no tags is not a function word', () async {
      expect((await spanFor([pos([])])).isFunctionWord, isFalse);
    });
  });

  test('a dictionary error propagates to the caller', () async {
    dictionary.error = StateError('database closed');

    await expectLater(glosser.gloss('魔王'), throwsStateError);
  });
}
