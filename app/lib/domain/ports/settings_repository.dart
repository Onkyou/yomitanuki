import '../models/anki_settings.dart';

/// Persists the user's settings (WP5). Implemented by the `shared_preferences`
/// adapter and by the in-memory fake in every other test.
abstract interface class SettingsRepository {
  /// The stored settings, or [AnkiSettings.defaults] when nothing is stored.
  Future<AnkiSettings> loadAnkiSettings();

  Future<void> saveAnkiSettings(AnkiSettings settings);

  /// Whether each tapped crop and its reading is saved for scoring (D6a.4).
  /// Off when nothing is stored.
  Future<bool> loadSaveCrops();

  Future<void> saveSaveCrops(bool value);

  /// Whether the sheet translates the read line (D6c.5). On when nothing is
  /// stored.
  Future<bool> loadTranslateEnabled();

  Future<void> saveTranslateEnabled(bool value);

  /// Whether the reader keeps the screen awake (D6f.6). On when nothing is
  /// stored.
  Future<bool> loadKeepAwake();

  Future<void> saveKeepAwake(bool value);
}
