import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
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
    reasons: ['past', 'negative', 'potential'],
    entry: taberu,
  );
  const line = 'パンを食べられなかった。';

  LookupResult lookupFor(DictionaryEntry entry) => LookupResult(
    start: 0,
    length: entry.headword.length,
    surface: entry.headword,
    baseForm: entry.headword,
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
}
