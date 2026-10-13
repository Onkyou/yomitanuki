import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';

void main() {
  test('defaults match the Frieren deck and note type (PLAN section 1)', () {
    const d = AnkiSettings.defaults;

    expect(d.deck, 'Japanese::Frieren Vol. 1');
    expect(d.noteType, 'Frieren Vocab (JP→EN)');
    expect(d.fieldName(AnkiField.word), 'Word');
    expect(d.fieldName(AnkiField.reading), 'Reading');
    expect(d.fieldName(AnkiField.meaning), 'Meaning');
    expect(d.fieldName(AnkiField.example), 'Example');
    expect(d.fieldName(AnkiField.exampleEn), 'ExampleEN');
    expect(d.fieldName(AnkiField.note), 'Note');
  });

  test('copyWith and withFieldName return changed copies, by value', () {
    const d = AnkiSettings.defaults;

    final changed = d
        .copyWith(deck: 'Japanese::Other', noteType: 'Basic')
        .withFieldName(AnkiField.word, 'Front');

    expect(changed.deck, 'Japanese::Other');
    expect(changed.noteType, 'Basic');
    expect(changed.fieldName(AnkiField.word), 'Front');
    expect(changed.fieldName(AnkiField.reading), 'Reading');
    expect(d, AnkiSettings.defaults);
    expect(changed, isNot(equals(d)));
    expect(
      changed,
      equals(
        const AnkiSettings(
          deck: 'Japanese::Other',
          noteType: 'Basic',
          fieldNames: {
            AnkiField.word: 'Front',
            AnkiField.reading: 'Reading',
            AnkiField.meaning: 'Meaning',
            AnkiField.example: 'Example',
            AnkiField.exampleEn: 'ExampleEN',
            AnkiField.note: 'Note',
          },
        ),
      ),
    );
    expect(changed.hashCode, isNot(d.hashCode));
  });

  test('a missing field name falls back to the default', () {
    const partial = AnkiSettings(deck: 'D', noteType: 'T', fieldNames: {});

    expect(partial.fieldName(AnkiField.exampleEn), 'ExampleEN');
    expect(
      partial,
      const AnkiSettings(
        deck: 'D',
        noteType: 'T',
        fieldNames: {AnkiField.exampleEn: 'ExampleEN'},
      ),
    );
  });
}
