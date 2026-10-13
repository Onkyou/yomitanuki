import 'package:flutter/foundation.dart';

import '../../../domain/models/anki_settings.dart';
import '../../../domain/ports/settings_repository.dart';

/// State for the settings screen: the current [AnkiSettings], saved on every
/// edit through the [SettingsRepository] (WP5 D5.7).
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this._repository});

  final SettingsRepository _repository;

  AnkiSettings? _settings;
  String? _error;

  /// `null` until [load] completes.
  AnkiSettings? get settings => _settings;

  /// Why the last load or save failed, `null` after one succeeds.
  String? get error => _error;

  Future<void> load() async {
    try {
      _settings = await _repository.loadAnkiSettings();
      _error = null;
    } on Exception catch (e) {
      _settings = AnkiSettings.defaults;
      _error = 'Settings could not be loaded: $e';
    }
    notifyListeners();
  }

  Future<void> setDeck(String deck) => _update(_current.copyWith(deck: deck));

  Future<void> setNoteType(String noteType) =>
      _update(_current.copyWith(noteType: noteType));

  Future<void> setFieldName(AnkiField field, String name) =>
      _update(_current.withFieldName(field, name));

  Future<void> resetToDefaults() => _update(AnkiSettings.defaults);

  AnkiSettings get _current => _settings ?? AnkiSettings.defaults;

  /// Shows [next] at once and persists it; a failed save keeps the edit on
  /// screen and surfaces in [error], so nothing typed is silently lost.
  Future<void> _update(AnkiSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      await _repository.saveAnkiSettings(next);
      if (_error == null) return;
      _error = null;
    } on Exception catch (e) {
      _error = 'Settings could not be saved: $e';
    }
    notifyListeners();
  }
}
