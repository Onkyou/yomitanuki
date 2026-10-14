import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:yomitanuki/data/repositories/shared_preferences_settings_repository.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';

void main() {
  late SharedPreferencesAsync prefs;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
  });

  test('nothing stored loads the defaults', () async {
    final repo = SharedPreferencesSettingsRepository(prefs);

    expect(await repo.loadAnkiSettings(), AnkiSettings.defaults);
  });

  test('what is saved is what loads, through a second instance', () async {
    final changed = AnkiSettings.defaults
        .copyWith(deck: 'Japanese::Vol. 2', noteType: 'Basic')
        .withFieldName(AnkiField.exampleEn, 'Translation');

    await SharedPreferencesSettingsRepository(prefs).saveAnkiSettings(changed);

    expect(
      await SharedPreferencesSettingsRepository(prefs).loadAnkiSettings(),
      changed,
    );
  });

  test('a change to one field name alone survives the round trip', () async {
    final renamed = AnkiSettings.defaults.withFieldName(
      AnkiField.note,
      'Notes',
    );

    await SharedPreferencesSettingsRepository(prefs).saveAnkiSettings(renamed);

    final loaded = await SharedPreferencesSettingsRepository(prefs)
        .loadAnkiSettings();
    expect(loaded.fieldName(AnkiField.note), 'Notes');
    expect(loaded, renamed);
    expect(loaded, isNot(equals(AnkiSettings.defaults)));
    expect(await prefs.getKeys(), {'anki.field.note'});
  });

  test('the storage keys are pinned (D5.6)', () async {
    final all = AnkiSettings.defaults
        .copyWith(deck: 'D', noteType: 'T')
        .withFieldName(AnkiField.word, 'W')
        .withFieldName(AnkiField.reading, 'R')
        .withFieldName(AnkiField.meaning, 'M')
        .withFieldName(AnkiField.example, 'E')
        .withFieldName(AnkiField.exampleEn, 'EE')
        .withFieldName(AnkiField.note, 'N');

    await SharedPreferencesSettingsRepository(prefs).saveAnkiSettings(all);

    expect(await prefs.getKeys(), {
      'anki.deck',
      'anki.noteType',
      'anki.field.word',
      'anki.field.reading',
      'anki.field.meaning',
      'anki.field.example',
      'anki.field.exampleEn',
      'anki.field.note',
    });
    expect(await prefs.getString('anki.field.exampleEn'), 'EE');
  });

  test('saving the defaults clears the stored override', () async {
    final repo = SharedPreferencesSettingsRepository(prefs);
    await repo.saveAnkiSettings(AnkiSettings.defaults.copyWith(deck: 'X'));

    await repo.saveAnkiSettings(AnkiSettings.defaults);

    expect(await prefs.getKeys(), isEmpty);
    expect(await repo.loadAnkiSettings(), AnkiSettings.defaults);
  });

  test('saving crops is off by default and the flag round-trips', () async {
    final repo = SharedPreferencesSettingsRepository(prefs);
    expect(await repo.loadSaveCrops(), isFalse);

    await repo.saveSaveCrops(true);

    expect(await prefs.getKeys(), {'debug.saveCrops'});
    expect(
      await SharedPreferencesSettingsRepository(prefs).loadSaveCrops(),
      isTrue,
    );
  });

  test('switching crops off removes the key', () async {
    final repo = SharedPreferencesSettingsRepository(prefs);
    await repo.saveSaveCrops(true);

    await repo.saveSaveCrops(false);

    expect(await prefs.getKeys(), isEmpty);
    expect(await repo.loadSaveCrops(), isFalse);
  });
}
