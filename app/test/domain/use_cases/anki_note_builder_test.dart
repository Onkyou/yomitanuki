import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/use_cases/anki_note_builder.dart';

import '../../fakes/fake_dictionary.dart';

void main() {
  const taberu = DictionaryEntry(
    id: 1358280,
    headword: '食べる',
    reading: 'たべる',
    senses: [
      Sense(glosses: ['to eat'], partsOfSpeech: ['v1', 'vt']),
      Sense(
        glosses: ['to live on (e.g. a salary)', 'to live off', 'to subsist on'],
        partsOfSpeech: ['v1', 'vt'],
      ),
    ],
    isCommon: true,
  );
  const lookup = LookupResult(
    start: 3,
    length: 8,
    surface: '食べられなかった',
    baseForm: '食べる',
    matchedReading: 'たべる',
    reasons: ['past', 'negative', 'potential'],
    entry: taberu,
    matchedSenseIndexes: [],
  );
  const line = 'パンを食べられなかった。';

  LookupResult lookupFor(DictionaryEntry entry) => LookupResult(
    start: 0,
    length: entry.headword.length,
    surface: entry.headword,
    baseForm: entry.headword,
    matchedReading: entry.reading,
    reasons: const [],
    entry: entry,
    matchedSenseIndexes: const [],
  );

  test('maps the entry onto the configured field names (D5.5, D6d)', () {
    const builder = AnkiNoteBuilder();

    final note = builder.build(
      lookup: lookup,
      contextLine: line,
      settings: AnkiSettings.defaults,
    );

    expect(note.deck, 'Japanese::Frieren Vol. 1');
    expect(note.noteType, 'Frieren Vocab (JP→EN)');
    expect(note.fields, {
      'Word': '食べる',
      'Reading': 'たべる',
      'Meaning': '1. to eat<br>2. to live on (e.g. a salary); to live off; to subsist on',
      'Example': 'パンを<b>食べられなかった</b>。',
      'ExampleEN': '',
      'Note': '',
    });
    expect(note.tags, ['yomitanuki']);
  });

  test('a kana spelling of an entry is the word, read as itself (ビール)', () {
    const beer = DictionaryEntry(
      id: 1104550,
      headword: '麦酒',
      reading: 'ばくしゅ',
      senses: [
        Sense(glosses: ['beer'], partsOfSpeech: ['n']),
      ],
      isCommon: false,
    );

    final note = const AnkiNoteBuilder().build(
      lookup: const LookupResult(
        start: 0,
        length: 4,
        surface: 'ビール',
        baseForm: 'ビール',
        matchedReading: 'ビール',
        reasons: [],
        entry: beer,
        matchedSenseIndexes: [],
      ),
      contextLine: 'ビールを飲む',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Word'], 'ビール');
    expect(note.fields['Reading'], 'ビール');
    expect(note.fields['Meaning'], 'beer');
  });

  test('an inflected surface still files under the entry headword', () {
    final note = const AnkiNoteBuilder().build(
      lookup: const LookupResult(
        start: 0,
        length: 3,
        surface: '食べた',
        baseForm: '食べる',
        matchedReading: 'たべる',
        reasons: ['past'],
        entry: taberu,
        matchedSenseIndexes: [],
      ),
      contextLine: '食べた',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Word'], '食べる');
    expect(note.fields['Reading'], 'たべる');
  });

  test('a kana word whose entry is written in kanji stays kana (D6d.1)', () {
    const chotto = DictionaryEntry(
      id: 1,
      headword: '一寸',
      reading: 'ちょっと',
      senses: [
        Sense(glosses: ['a little'], partsOfSpeech: ['adv']),
      ],
      isCommon: true,
    );

    final note = const AnkiNoteBuilder().build(
      lookup: const LookupResult(
        start: 5,
        length: 4,
        surface: 'ちょっと',
        baseForm: 'ちょっと',
        matchedReading: 'ちょっと',
        reasons: [],
        entry: chotto,
        matchedSenseIndexes: [],
      ),
      contextLine: 'この魔法、ちょっと難しいね',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Word'], 'ちょっと');
    expect(note.fields['Reading'], 'ちょっと');
    expect(note.fields['Example'], 'この魔法、<b>ちょっと</b>難しいね');
  });

  group('Meaning (D6d.2)', () {
    const many = DictionaryEntry(
      id: 3,
      headword: '出る',
      reading: 'でる',
      senses: [
        Sense(glosses: ['to leave'], partsOfSpeech: ['v1']),
        Sense(glosses: ['to appear', 'to come out'], partsOfSpeech: ['v1']),
        Sense(glosses: ['to attend'], partsOfSpeech: ['v1']),
        Sense(glosses: ['to graduate'], partsOfSpeech: ['v1']),
        Sense(glosses: ['to exit'], partsOfSpeech: ['v1']),
      ],
      isCommon: true,
    );

    LookupResult matching(List<int> indexes) => LookupResult(
      start: 0,
      length: 2,
      surface: '出た',
      baseForm: '出る',
      matchedReading: 'でる',
      reasons: const ['past'],
      entry: many,
      matchedSenseIndexes: indexes,
    );

    String meaningOf(List<int> indexes) => const AnkiNoteBuilder()
        .build(
          lookup: matching(indexes),
          contextLine: '出た',
          settings: AnkiSettings.defaults,
        )
        .fields['Meaning']!;

    test('an exact match lists the first three senses, numbered', () {
      expect(
        meaningOf(const []),
        '1. to leave<br>2. to appear; to come out<br>3. to attend',
      );
    });

    test('the matched senses come first, in order, then the rest, three '
        'in all', () {
      expect(
        meaningOf(const [1, 3]),
        '1. to appear; to come out<br>2. to graduate<br>3. to leave',
      );
    });

    test('one matched sense leads and is followed by the first two others', () {
      expect(
        meaningOf(const [4]),
        '1. to exit<br>2. to leave<br>3. to appear; to come out',
      );
    });

    test('more than three matched senses are still capped at three', () {
      expect(
        meaningOf(const [0, 1, 2, 3, 4]),
        '1. to leave<br>2. to appear; to come out<br>3. to attend',
      );
    });

    test('indexes outside the senses are ignored', () {
      expect(
        meaningOf(const [9, -1, 2]),
        '1. to attend<br>2. to leave<br>3. to appear; to come out',
      );
    });

    test('a single matched sense of a two-sense entry still lists both', () {
      final note = const AnkiNoteBuilder().build(
        lookup: const LookupResult(
          start: 0,
          length: 3,
          surface: '食べた',
          baseForm: '食べる',
          matchedReading: 'たべる',
          reasons: ['past'],
          entry: taberu,
          matchedSenseIndexes: [1],
        ),
        contextLine: '食べた',
        settings: AnkiSettings.defaults,
      );

      expect(
        note.fields['Meaning'],
        '1. to live on (e.g. a salary); to live off; to subsist on'
        '<br>2. to eat',
      );
    });
  });

  group('Example (D6d.3)', () {
    LookupResult at(int start, int length) => LookupResult(
      start: start,
      length: length,
      surface: 'x',
      baseForm: '食べる',
      matchedReading: 'たべる',
      reasons: const [],
      entry: taberu,
      matchedSenseIndexes: const [],
    );

    String exampleOf(LookupResult l, String text, {LineGloss? gloss}) =>
        const AnkiNoteBuilder()
            .build(
              lookup: l,
              contextLine: text,
              settings: AnkiSettings.defaults,
              gloss: gloss,
            )
            .fields['Example']!;

    test('without a gloss the target is bold and the rest is escaped', () {
      expect(exampleOf(at(2, 2), 'A<食べ>&'), 'A&lt;<b>食べ</b>&gt;&amp;');
    });

    test('a target at either end of the line is bold there', () {
      expect(exampleOf(at(0, 2), '食べた'), '<b>食べ</b>た');
      expect(exampleOf(at(1, 2), 'パ食べ'), 'パ<b>食べ</b>');
    });

    test('a target that does not fit the line leaves the line plain', () {
      expect(exampleOf(at(2, 5), 'パン<'), 'パン&lt;');
      expect(exampleOf(at(-1, 2), 'パン'), 'パン');
      expect(exampleOf(at(0, 0), 'パン'), 'パン');
    });

    test('with a gloss the other words carry <ruby>, the target is bold and '
        'bare', () {
      const gloss = LineGloss('魔王を倒した勇者', [
        GlossSpan(
          start: 0,
          length: 2,
          surface: '魔王',
          reading: 'まおう',
          gloss: 'Satan',
          baseForm: '魔王',
          ruby: [RubySegment('魔王', 'まおう')],
        ),
        GlossSpan(start: 2, length: 1, surface: 'を', ruby: [RubySegment('を')]),
        GlossSpan(
          start: 3,
          length: 3,
          surface: '倒した',
          reading: 'たおす',
          gloss: 'to throw down',
          baseForm: '倒す',
          ruby: [RubySegment('倒', 'たお'), RubySegment('した')],
        ),
        GlossSpan(
          start: 6,
          length: 2,
          surface: '勇者',
          reading: 'ゆうしゃ',
          gloss: 'hero',
          baseForm: '勇者',
          ruby: [RubySegment('勇者', 'ゆうしゃ')],
        ),
      ]);

      expect(
        exampleOf(at(0, 2), '魔王を倒した勇者', gloss: gloss),
        '<b>魔王</b>を<ruby>倒<rt>たお</rt></ruby>した'
        '<ruby>勇者<rt>ゆうしゃ</rt></ruby>',
      );
    });
  });

  test('a single sense is not numbered', () {
    const entry = DictionaryEntry(
      id: 1,
      headword: '猫',
      reading: 'ねこ',
      senses: [
        Sense(glosses: ['cat (esp. the domestic cat)'], partsOfSpeech: ['n']),
      ],
      isCommon: true,
    );

    final note = const AnkiNoteBuilder().build(
      lookup: lookupFor(entry),
      contextLine: '猫がいる',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Meaning'], 'cat (esp. the domestic cat)');
  });

  test('field text is HTML: & < > are escaped in every value', () {
    const entry = DictionaryEntry(
      id: 2,
      headword: 'R&D',
      reading: 'a<b',
      senses: [
        Sense(glosses: ['x > y', 'p & q'], partsOfSpeech: ['n']),
        Sense(glosses: ['<i>not markup</i>'], partsOfSpeech: ['n']),
      ],
      isCommon: false,
    );

    final note = const AnkiNoteBuilder().build(
      lookup: lookupFor(entry),
      contextLine: 'A&B <C>',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Word'], 'R&amp;D');
    expect(note.fields['Reading'], 'a&lt;b');
    expect(
      note.fields['Meaning'],
      '1. x &gt; y; p &amp; q<br>2. &lt;i&gt;not markup&lt;/i&gt;',
    );
    expect(note.fields['Example'], '<b>A&amp;B</b> &lt;C&gt;');
  });

  test('a two-line context line becomes two HTML lines', () {
    final note = const AnkiNoteBuilder().build(
      lookup: LookupResult(
        start: 4,
        length: 8,
        surface: lookup.surface,
        baseForm: lookup.baseForm,
        matchedReading: lookup.matchedReading,
        reasons: lookup.reasons,
        entry: taberu,
        matchedSenseIndexes: const [],
      ),
      contextLine: 'パンを\n食べられなかった。',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Example'], 'パンを<br><b>食べられなかった</b>。');
  });

  test('renamed fields and another deck follow the settings, trimmed', () {
    final settings = AnkiSettings.defaults
        .copyWith(deck: ' Japanese::Test ', noteType: 'Basic ')
        .withFieldName(AnkiField.word, ' Front')
        .withFieldName(AnkiField.meaning, 'Back');

    final note = const AnkiNoteBuilder().build(
      lookup: lookup,
      contextLine: line,
      settings: settings,
    );

    expect(note.deck, 'Japanese::Test');
    expect(note.noteType, 'Basic');
    expect(note.fields['Front'], '食べる');
    expect(note.fields['Back'], startsWith('1. to eat'));
    expect(note.fields.containsKey('Word'), isFalse);
  });

  test(
    'two slots mapped to one field name throw instead of losing a field',
    () {
      final collision = AnkiSettings.defaults.withFieldName(
        AnkiField.reading,
        'Word',
      );

      expect(
        () => const AnkiNoteBuilder().build(
          lookup: lookup,
          contextLine: line,
          settings: collision,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Word'),
          ),
        ),
      );
    },
  );

  test('an empty deck, note type or field name throws', () {
    const builder = AnkiNoteBuilder();
    AnkiNote call(AnkiSettings s) =>
        builder.build(lookup: lookup, contextLine: line, settings: s);

    expect(
      () => call(AnkiSettings.defaults.copyWith(deck: '  ')),
      throwsArgumentError,
    );
    expect(
      () => call(AnkiSettings.defaults.copyWith(noteType: '')),
      throwsArgumentError,
    );
    expect(
      () => call(AnkiSettings.defaults.withFieldName(AnkiField.note, ' ')),
      throwsArgumentError,
    );
  });
  group('Example (English) (D6c.4)', () {
    test(
      'a word note carries the translation of its context line, escaped',
      () {
        final note = const AnkiNoteBuilder().build(
          lookup: lookup,
          contextLine: line,
          settings: AnkiSettings.defaults,
          contextTranslation: 'I couldn\'t eat <the> bread & more.',
        );

        expect(
          note.fields['ExampleEN'],
          'I couldn\'t eat &lt;the&gt; bread &amp; more.',
        );
      },
    );

    test('no translation keeps the field empty', () {
      final note = const AnkiNoteBuilder().build(
        lookup: lookup,
        contextLine: line,
        settings: AnkiSettings.defaults,
      );

      expect(note.fields['ExampleEN'], '');
    });

    test('a sentence note carries it as its Meaning, never in ExampleEN', () {
      const gloss = LineGloss('パン', [
        GlossSpan(
          start: 0,
          length: 2,
          surface: 'パン',
          ruby: [RubySegment('パン')],
        ),
      ]);

      final with_ = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
        contextTranslation: 'Bread.\nSecond line.',
      );
      final without = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
      );

      expect(with_.fields['Meaning'], 'Bread.<br>Second line.');
      expect(with_.fields['ExampleEN'], '');
      expect(without.fields['Meaning'], '');
      expect(without.fields['ExampleEN'], '');
    });

    test('renamed Example (English) field follows the settings', () {
      final settings = AnkiSettings.defaults.withFieldName(
        AnkiField.exampleEn,
        'Translation',
      );

      final note = const AnkiNoteBuilder().build(
        lookup: lookup,
        contextLine: line,
        settings: settings,
        contextTranslation: 'Bread.',
      );

      expect(note.fields['Translation'], 'Bread.');
    });
  });
  group('buildSentence (D6b.3)', () {
    const gloss = LineGloss('魔王が<食べた>&本', [
      GlossSpan(
        start: 0,
        length: 2,
        surface: '魔王',
        reading: 'まおう',
        gloss: 'devil king, demon lord',
        baseForm: '魔王',
        ruby: [RubySegment('魔王', 'まおう')],
      ),
      GlossSpan(start: 2, length: 2, surface: 'が<', ruby: [RubySegment('が<')]),
      GlossSpan(
        start: 4,
        length: 3,
        surface: '食べた',
        reading: 'たべる',
        gloss: 'to eat & drink',
        baseForm: '食べる',
        ruby: [RubySegment('食', 'た'), RubySegment('べた')],
      ),
      GlossSpan(
        start: 7,
        length: 3,
        surface: '>&本',
        ruby: [RubySegment('>&本')],
      ),
    ]);

    test('the line is the word, the furigana line the reading, the glosses '
        'the crib (D6d.4)', () {
      final note = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
      );

      expect(note.deck, 'Japanese::Frieren Vol. 1');
      expect(note.noteType, 'Frieren Vocab (JP→EN)');
      expect(note.fields, {
        'Word': '魔王が&lt;食べた&gt;&amp;本',
        'Reading':
            '<ruby>魔王<rt>まおう</rt></ruby>が&lt;'
            '<ruby>食<rt>た</rt></ruby>べた&gt;&amp;本',
        'Meaning':
            '<details><summary>Words</summary>'
            '魔王: devil king, demon lord<br>食べた: to eat &amp; drink'
            '</details>',
        'Example': '',
        'ExampleEN': '',
        'Note': '',
      });
      expect(note.tags, ['yomitanuki', 'sentence']);
    });

    test('the translation is the answer, the glosses follow in <details>', () {
      final note = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
        contextTranslation: 'The demon king <ate> & left.\nBye.',
      );

      expect(
        note.fields['Meaning'],
        'The demon king &lt;ate&gt; &amp; left.<br>Bye.<br>'
        '<details><summary>Words</summary>'
        '魔王: devil king, demon lord<br>食べた: to eat &amp; drink'
        '</details>',
      );
      expect(note.fields['ExampleEN'], '');
    });

    test('no matched span leaves the translation alone, no <details>', () {
      final note = const AnkiNoteBuilder().buildSentence(
        gloss: const LineGloss('ええと', [
          GlossSpan(
            start: 0,
            length: 3,
            surface: 'ええと',
            ruby: [RubySegment('ええと')],
          ),
        ]),
        settings: AnkiSettings.defaults,
        contextTranslation: 'Um.',
      );

      expect(note.fields['Meaning'], 'Um.');
    });

    test('the sentence note type applies when set, else the note type', () {
      final withType = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults.copyWith(
          sentenceNoteType: ' Frieren Sentences ',
        ),
      );
      final blank = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults.copyWith(sentenceNoteType: '  '),
      );
      final unset = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
      );

      expect(withType.noteType, 'Frieren Sentences');
      expect(blank.noteType, 'Frieren Vocab (JP→EN)');
      expect(unset.noteType, 'Frieren Vocab (JP→EN)');
      expect(withType.deck, 'Japanese::Frieren Vol. 1');
    });

    test('renamed fields follow the settings, like a word note', () {
      final settings = AnkiSettings.defaults
          .withFieldName(AnkiField.word, 'Front')
          .withFieldName(AnkiField.note, 'Tag');

      final note = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: settings,
      );

      expect(note.fields['Front'], startsWith('魔王が'));
      expect(note.fields['Tag'], '');
      expect(note.fields.containsKey('Word'), isFalse);
    });

    test('a line with several lines becomes HTML lines', () {
      final note = const AnkiNoteBuilder().buildSentence(
        gloss: const LineGloss('一行目\n二行目', [
          GlossSpan(
            start: 0,
            length: 7,
            surface: '一行目\n二行目',
            ruby: [RubySegment('一行目\n二行目')],
          ),
        ]),
        settings: AnkiSettings.defaults,
      );

      expect(note.fields['Word'], '一行目<br>二行目');
      expect(note.fields['Meaning'], '');
    });

    test('settings the builder refuses throw, like for a word note', () {
      expect(
        () => const AnkiNoteBuilder().buildSentence(
          gloss: gloss,
          settings: AnkiSettings.defaults.copyWith(deck: ' '),
        ),
        throwsArgumentError,
      );
    });
  });

  // The whole-note maps the WP6d spec promises, one per fixture, so a change
  // to any single field shows up as one readable diff.
  group('field maps (WP6d)', () {
    const taberareGloss = LineGloss('食べられなかった', [
      GlossSpan(
        start: 0,
        length: 8,
        surface: '食べられなかった',
        reading: 'たべる',
        gloss: 'to eat',
        baseForm: '食べる',
        ruby: [RubySegment('食', 'た'), RubySegment('べられなかった')],
      ),
    ]);

    test('食べられなかった: word note and sentence note', () {
      const builder = AnkiNoteBuilder();

      final word = builder.build(
        lookup: taberareNakattaResult,
        contextLine: '食べられなかった',
        settings: AnkiSettings.defaults,
        contextTranslation: 'I could not eat it.',
        gloss: taberareGloss,
      );
      final sentence = builder.buildSentence(
        gloss: taberareGloss,
        settings: AnkiSettings.defaults,
        contextTranslation: 'I could not eat it.',
      );

      expect(word.fields, {
        'Word': '食べる',
        'Reading': 'たべる',
        'Meaning': '1. to eat<br>2. to live on (e.g. a salary)',
        'Example': '<b>食べられなかった</b>',
        'ExampleEN': 'I could not eat it.',
        'Note': '',
      });
      expect(word.tags, ['yomitanuki']);
      expect(sentence.fields, {
        'Word': '食べられなかった',
        'Reading': '<ruby>食<rt>た</rt></ruby>べられなかった',
        'Meaning':
            'I could not eat it.<br><details><summary>Words</summary>'
            '食べられなかった: to eat</details>',
        'Example': '',
        'ExampleEN': '',
        'Note': '',
      });
      expect(sentence.tags, ['yomitanuki', 'sentence']);
    });

    test('ビール (entry 麦酒): the kana spelling stays, the target is bold', () {
      const beer = DictionaryEntry(
        id: 1104550,
        headword: '麦酒',
        reading: 'ばくしゅ',
        senses: [
          Sense(glosses: ['beer'], partsOfSpeech: ['n']),
        ],
        isCommon: false,
      );

      final note = const AnkiNoteBuilder().build(
        lookup: const LookupResult(
          start: 0,
          length: 3,
          surface: 'ビール',
          baseForm: 'ビール',
          matchedReading: 'ビール',
          reasons: [],
          entry: beer,
          matchedSenseIndexes: [],
        ),
        contextLine: 'ビールを飲む',
        settings: AnkiSettings.defaults,
      );

      expect(note.fields, {
        'Word': 'ビール',
        'Reading': 'ビール',
        'Meaning': 'beer',
        'Example': '<b>ビール</b>を飲む',
        'ExampleEN': '',
        'Note': '',
      });
    });

    test('魔王を倒した勇者: word note on 魔王, sentence note on the line', () {
      const gloss = LineGloss('魔王を倒した勇者', [
        GlossSpan(
          start: 0,
          length: 2,
          surface: '魔王',
          reading: 'まおう',
          gloss: 'devil king, demon lord',
          baseForm: '魔王',
          ruby: [RubySegment('魔王', 'まおう')],
        ),
        GlossSpan(start: 2, length: 1, surface: 'を', ruby: [RubySegment('を')]),
        GlossSpan(
          start: 3,
          length: 3,
          surface: '倒した',
          reading: 'たおす',
          gloss: 'to throw down',
          baseForm: '倒す',
          ruby: [RubySegment('倒', 'たお'), RubySegment('した')],
        ),
        GlossSpan(
          start: 6,
          length: 2,
          surface: '勇者',
          reading: 'ゆうしゃ',
          gloss: 'hero',
          baseForm: '勇者',
          ruby: [RubySegment('勇者', 'ゆうしゃ')],
        ),
      ]);
      const builder = AnkiNoteBuilder();

      final word = builder.build(
        lookup: LookupResult(
          start: 0,
          length: 2,
          surface: '魔王',
          baseForm: '魔王',
          matchedReading: 'まおう',
          reasons: const [],
          entry: FakeDictionary.defaultEntries[2],
          matchedSenseIndexes: const [],
        ),
        contextLine: '魔王を倒した勇者',
        settings: AnkiSettings.defaults,
        contextTranslation: 'The hero who beat the demon king.',
        gloss: gloss,
      );
      final sentence = builder.buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
        contextTranslation: 'The hero who beat the demon king.',
      );

      expect(word.fields, {
        'Word': '魔王',
        'Reading': 'まおう',
        'Meaning': 'devil king; demon lord',
        'Example':
            '<b>魔王</b>を<ruby>倒<rt>たお</rt></ruby>した'
            '<ruby>勇者<rt>ゆうしゃ</rt></ruby>',
        'ExampleEN': 'The hero who beat the demon king.',
        'Note': '',
      });
      expect(sentence.fields, {
        'Word': '魔王を倒した勇者',
        'Reading':
            '<ruby>魔王<rt>まおう</rt></ruby>を<ruby>倒<rt>たお</rt></ruby>した'
            '<ruby>勇者<rt>ゆうしゃ</rt></ruby>',
        'Meaning':
            'The hero who beat the demon king.<br>'
            '<details><summary>Words</summary>'
            '魔王: devil king, demon lord<br>倒した: to throw down<br>勇者: hero'
            '</details>',
        'Example': '',
        'ExampleEN': '',
        'Note': '',
      });
    });
  });
}
