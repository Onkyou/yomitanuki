import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';
import 'package:yomitanuki/domain/use_cases/anki_note_builder.dart';

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
  );

  test('maps the entry onto the configured field names (D5.5)', () {
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
      'Example': 'パンを食べられなかった。',
      'ExampleEN': '',
      'Note': '',
    });
    expect(note.tags, isEmpty);
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
      ),
      contextLine: '食べた',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Word'], '食べる');
    expect(note.fields['Reading'], 'たべる');
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
    expect(note.fields['Example'], 'A&amp;B &lt;C&gt;');
  });

  test('a two-line context line becomes two HTML lines', () {
    final note = const AnkiNoteBuilder().build(
      lookup: lookup,
      contextLine: 'パンを\n食べられなかった。',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Example'], 'パンを<br>食べられなかった。');
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

    test('a sentence note carries it too, and stays empty without one', () {
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

      expect(with_.fields['ExampleEN'], 'Bread.<br>Second line.');
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

    test('the line is the word and the example, the readings and glosses '
        'fill the rest', () {
      final note = const AnkiNoteBuilder().buildSentence(
        gloss: gloss,
        settings: AnkiSettings.defaults,
      );

      expect(note.deck, 'Japanese::Frieren Vol. 1');
      expect(note.noteType, 'Frieren Vocab (JP→EN)');
      expect(note.fields, {
        'Word': '魔王が&lt;食べた&gt;&amp;本',
        'Reading': 'まおうが&lt;たべた&gt;&amp;本',
        'Meaning': '魔王: devil king, demon lord<br>食べた: to eat &amp; drink',
        'Example': '魔王が&lt;食べた&gt;&amp;本',
        'ExampleEN': '',
        'Note': 'sentence',
      });
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
      expect(note.fields['Tag'], 'sentence');
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
}
