import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/anki/anki_note_builder.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/dictionary_entry.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';

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
    const single = LookupResult(
      start: 0,
      length: 1,
      surface: '猫',
      baseForm: '猫',
      reasons: [],
      entry: entry,
    );

    final note = const AnkiNoteBuilder().build(
      lookup: single,
      contextLine: '猫がいる',
      settings: AnkiSettings.defaults,
    );

    expect(note.fields['Meaning'], 'cat (esp. the domestic cat)');
  });

  test('renamed fields and another deck follow the settings', () {
    final settings = AnkiSettings.defaults
        .copyWith(deck: 'Japanese::Test', noteType: 'Basic')
        .withFieldName(AnkiField.word, 'Front')
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
}
