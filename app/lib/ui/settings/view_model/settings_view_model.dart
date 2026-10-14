import 'package:flutter/foundation.dart';

import '../../../domain/models/anki_settings.dart';
import '../../../domain/ports/settings_repository.dart';

/// State for the settings screen: the current [AnkiSettings], saved on every
/// valid edit through the [SettingsRepository] (WP5 D5.7, D5.8), and the
/// diagnostics switch for saving OCR crops (WP6a D6a.4).
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this._repository});

  final SettingsRepository _repository;

  AnkiSettings? _settings;
  bool _saveCrops = false;
  String? _error;
  Exception? _lastFailure;

  /// `null` until [load] completes.
  AnkiSettings? get settings => _settings;

  /// Whether each tapped crop and its reading is saved for scoring.
  bool get saveCrops => _saveCrops;

  /// What is wrong, for the user: a fixed sentence for a failed load or
  /// save, or the first of [AnkiSettings.problems] while the edit is
  /// invalid. `null` once a save succeeds.
  String? get error => _error;

  /// The exception behind a "could not be loaded/saved" [error], for the
  /// log; never shown. `null` when [error] is not a failure.
  Exception? get lastFailure => _lastFailure;

  Future<void> load() async {
    try {
      _settings = await _repository.loadAnkiSettings();
      _setError(null);
    } on Exception catch (e) {
      _settings = AnkiSettings.defaults;
      _setError('Settings could not be loaded.', e);
    }
    // Read on its own: a failing diagnostics flag must not replace Anki
    // settings that did load (WP6a review).
    try {
      _saveCrops = await _repository.loadSaveCrops();
    } on Exception catch (e) {
      _saveCrops = false;
      _setError('Settings could not be loaded.', e);
    }
    notifyListeners();
  }

  Future<void> setDeck(String deck) => _update(_current.copyWith(deck: deck));

  Future<void> setNoteType(String noteType) =>
      _update(_current.copyWith(noteType: noteType));

  Future<void> setFieldName(AnkiField field, String name) =>
      _update(_current.withFieldName(field, name));

  /// Shows [value] at once; a failed save keeps it on screen and surfaces in
  /// [error], like an Anki edit.
  Future<void> setSaveCrops(bool value) async {
    _saveCrops = value;
    notifyListeners();
    try {
      await _repository.saveSaveCrops(value);
      // A success clears a stale banner, like `_update` does (D5.7).
      if (_saveCrops == value && _error != null) {
        _setError(null);
        notifyListeners();
      }
    } on Exception catch (e) {
      if (_saveCrops != value) return;
      _setError('Settings could not be saved.', e);
      notifyListeners();
    }
  }

  Future<void> resetToDefaults() => _update(AnkiSettings.defaults);

  AnkiSettings get _current => _settings ?? AnkiSettings.defaults;

  /// Shows [next] at once. An invalid [next] is reported and not persisted,
  /// so the stored settings always build a note; a valid one is saved, and
  /// a failed save keeps the edit on screen and surfaces in [error], so
  /// nothing typed is silently lost. A save that answers after a newer edit
  /// has replaced [next] is ignored: the newer save reports for itself.
  Future<void> _update(AnkiSettings next) async {
    _settings = next;
    final problems = next.problems;
    if (problems.isNotEmpty) {
      _setError(problems.first);
      notifyListeners();
      return;
    }
    notifyListeners();
    try {
      await _repository.saveAnkiSettings(next);
      if (!identical(next, _settings) || _error == null) return;
      _setError(null);
    } on Exception catch (e) {
      if (!identical(next, _settings)) return;
      _setError('Settings could not be saved.', e);
    }
    notifyListeners();
  }

  void _setError(String? message, [Exception? cause]) {
    _error = message;
    _lastFailure = cause;
    if (cause != null) {
      // The log sink until logging-strategy picks one for the app.
      debugPrint('SettingsViewModel: $message $cause');
    }
  }
}
