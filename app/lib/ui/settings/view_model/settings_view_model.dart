import 'package:flutter/foundation.dart';

import '../../../domain/models/anki_settings.dart';
import '../../../domain/models/translation_status.dart';
import '../../../domain/ports/sentence_translator.dart';
import '../../../domain/ports/settings_repository.dart';

/// State for the settings screen: the current [AnkiSettings], saved on every
/// valid edit through the [SettingsRepository] (WP5 D5.7, D5.8), and the
/// diagnostics switch for saving OCR crops (WP6a D6a.4), and the switch for
/// sentence translation with what the device says about it (WP6c D6c.5).
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this._repository, required this._translator});

  final SettingsRepository _repository;
  final SentenceTranslator _translator;

  AnkiSettings? _settings;
  bool _saveCrops = false;
  bool _translateEnabled = true;
  TranslationStatus? _translationStatus;
  String? _error;
  Exception? _lastFailure;

  /// `null` until [load] completes.
  AnkiSettings? get settings => _settings;

  /// Whether each tapped crop and its reading is saved for scoring.
  bool get saveCrops => _saveCrops;

  /// Whether the sheet translates the read line.
  bool get translateEnabled => _translateEnabled;

  /// Whether the device can translate Japanese to English offline; `null`
  /// until [load] completes, and for good if the query failed.
  TranslationStatus? get translationStatus => _translationStatus;

  /// [translationStatus] as a sentence for the switch's subtitle; empty
  /// while unknown.
  String get translationStatusText => switch (_translationStatus) {
    TranslationStatus.installed =>
      'Japanese → English is installed for offline use.',
    TranslationStatus.downloadNeeded =>
      'Download Japanese and English under Settings › Apps › Translate › '
          'Downloaded Languages to translate offline.',
    TranslationStatus.unsupported =>
      'This device cannot translate Japanese to English.',
    TranslationStatus.requiresNewerOs => 'Sentence translation needs iOS 26.',
    null => '',
  };

  /// What is wrong, for the user: a fixed sentence for a failed load or
  /// save, or the first of [AnkiSettings.problems] while the edit is
  /// invalid. `null` once a save succeeds.
  String? get error => _error;

  /// The exception behind a "could not be loaded/saved" [error], for the
  /// log; never shown. `null` when [error] is not a failure.
  Exception? get lastFailure => _lastFailure;

  Future<void> load() async {
    // Asked first: it takes a few availability queries, and nothing else here
    // depends on it. Only a subtitle, so a failed query costs the text, not
    // the screen.
    final status = _translator.status().then<TranslationStatus?>(
      (s) => s,
      onError: (Object e) {
        debugPrint('SettingsViewModel: translation status failed $e');
        return null;
      },
    );
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
    try {
      _translateEnabled = await _repository.loadTranslateEnabled();
    } on Exception catch (e) {
      _translateEnabled = true;
      _setError('Settings could not be loaded.', e);
    }
    _translationStatus = await status;
    notifyListeners();
  }

  Future<void> setDeck(String deck) => _update(_current.copyWith(deck: deck));

  Future<void> setNoteType(String noteType) =>
      _update(_current.copyWith(noteType: noteType));

  /// Blank is kept as typed and means "same as the note type".
  Future<void> setSentenceNoteType(String noteType) =>
      _update(_current.copyWith(sentenceNoteType: noteType));

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

  /// Like [setSaveCrops].
  Future<void> setTranslateEnabled(bool value) async {
    _translateEnabled = value;
    notifyListeners();
    try {
      await _repository.saveTranslateEnabled(value);
      if (_translateEnabled == value && _error != null) {
        _setError(null);
        notifyListeners();
      }
    } on Exception catch (e) {
      if (_translateEnabled != value) return;
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
