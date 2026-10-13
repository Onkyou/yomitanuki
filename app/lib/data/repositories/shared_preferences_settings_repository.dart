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
  static String _fieldKey(AnkiField field) => 'anki.field.${field.name}';

  @override
  Future<AnkiSettings> loadAnkiSettings() async {
    const defaults = AnkiSettings.defaults;
    return AnkiSettings(
      deck: await _prefs.getString(_deckKey) ?? defaults.deck,
      noteType: await _prefs.getString(_noteTypeKey) ?? defaults.noteType,
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
    for (final field in AnkiField.values) {
      await _put(
        _fieldKey(field),
        settings.fieldName(field),
        defaults.fieldName(field),
      );
    }
  }

  Future<void> _put(String key, String value, String defaultValue) =>
      value == defaultValue ? _prefs.remove(key) : _prefs.setString(key, value);
}
