import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/anki_settings.dart';
import '../../domain/ports/settings_repository.dart';

/// [SettingsRepository] on `shared_preferences` (WP5 D5.6). One string key
/// per value; a key is written only when the value differs from its default
/// and removed otherwise, so "nothing stored" and "the defaults" are the
/// same state and a changed default reaches users who never edited it.
class SharedPreferencesSettingsRepository implements SettingsRepository {
  SharedPreferencesSettingsRepository(this._prefs);

  final SharedPreferencesAsync _prefs;

  static const _deckKey = 'anki.deck';
  static const _noteTypeKey = 'anki.noteType';
  static const _sentenceNoteTypeKey = 'anki.sentenceNoteType';
  static const _saveCropsKey = 'debug.saveCrops';
  static const _translateKey = 'translate.enabled';
  static const _keepAwakeKey = 'screen.keepAwake';
  static String _fieldKey(AnkiField field) => 'anki.field.${field.name}';

  @override
  Future<AnkiSettings> loadAnkiSettings() async {
    const defaults = AnkiSettings.defaults;
    return AnkiSettings(
      deck: await _prefs.getString(_deckKey) ?? defaults.deck,
      noteType: await _prefs.getString(_noteTypeKey) ?? defaults.noteType,
      sentenceNoteType: await _prefs.getString(_sentenceNoteTypeKey),
      fieldNames: {
        for (final field in AnkiField.values)
          field:
              await _prefs.getString(_fieldKey(field)) ??
              defaults.fieldName(field),
      },
    );
  }

  @override
  Future<void> saveAnkiSettings(AnkiSettings settings) async {
    const defaults = AnkiSettings.defaults;
    await _put(_deckKey, settings.deck, defaults.deck);
    await _put(_noteTypeKey, settings.noteType, defaults.noteType);
    // Blank means "same as the note type", which is also what nothing stored
    // means.
    final sentences = settings.sentenceNoteType?.trim();
    if (sentences == null || sentences.isEmpty) {
      await _prefs.remove(_sentenceNoteTypeKey);
    } else {
      await _prefs.setString(_sentenceNoteTypeKey, settings.sentenceNoteType!);
    }
    for (final field in AnkiField.values) {
      await _put(
        _fieldKey(field),
        settings.fieldName(field),
        defaults.fieldName(field),
      );
    }
  }

  @override
  Future<bool> loadSaveCrops() async =>
      await _prefs.getBool(_saveCropsKey) ?? false;

  @override
  Future<void> saveSaveCrops(bool value) => value
      ? _prefs.setBool(_saveCropsKey, true)
      : _prefs.remove(_saveCropsKey);

  @override
  Future<bool> loadTranslateEnabled() async =>
      await _prefs.getBool(_translateKey) ?? true;

  @override
  Future<void> saveTranslateEnabled(bool value) => value
      ? _prefs.remove(_translateKey)
      : _prefs.setBool(_translateKey, false);

  @override
  Future<bool> loadKeepAwake() async =>
      await _prefs.getBool(_keepAwakeKey) ?? true;

  @override
  Future<void> saveKeepAwake(bool value) => value
      ? _prefs.remove(_keepAwakeKey)
      : _prefs.setBool(_keepAwakeKey, false);

  Future<void> _put(String key, String value, String defaultValue) =>
      value == defaultValue ? _prefs.remove(key) : _prefs.setString(key, value);
}
