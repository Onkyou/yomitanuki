import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/ports/settings_repository.dart';

/// In-memory [SettingsRepository]: what was saved is what loads next, and
/// every save is recorded so a test can assert on the sequence.
///
/// Every call yields to the event loop before it answers, like a real
/// adapter does, so a caller's "before the await" and "after the await"
/// states are both observable. [failure] is read when the call is made and
/// thrown after that yield.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({this.stored});

  /// What [loadAnkiSettings] returns; `null` stands for "nothing stored yet".
  AnkiSettings? stored;

  /// Every argument [saveAnkiSettings] received, oldest first.
  final List<AnkiSettings> saved = [];

  /// What [loadSaveCrops] returns, and the last value [saveSaveCrops] stored.
  bool saveCrops = false;

  /// Every argument [saveSaveCrops] received, oldest first.
  final List<bool> savedSaveCrops = [];

  /// What [loadTranslateEnabled] returns, and the last value
  /// [saveTranslateEnabled] stored. On, like the real default.
  bool translateEnabled = true;

  /// Every argument [saveTranslateEnabled] received, oldest first.
  final List<bool> savedTranslateEnabled = [];

  /// What [loadKeepAwake] returns, and the last value [saveKeepAwake] stored.
  /// On, like the real default.
  bool keepAwake = true;

  /// Every argument [saveKeepAwake] received, oldest first.
  final List<bool> savedKeepAwake = [];

  /// When set, every call throws it, so error paths can be exercised.
  Exception? failure;

  /// When set, only the two save-crops calls throw it: the Anki calls still
  /// answer, so a partial load can be exercised.
  Exception? saveCropsFailure;

  /// When set, only the two translate-switch calls throw it.
  Exception? translateEnabledFailure;

  /// When set, only the two keep-awake calls throw it. These two calls yield
  /// a microtask, not a timer, and ignore [latency]: the view model makes
  /// them on every start, and a timer there would be pending at the end of
  /// every widget test that mounts the reader.
  Exception? keepAwakeFailure;

  /// How long a call takes to answer. Zero still yields once; a widget test
  /// that must see the frame between the edit and the answer sets a gap
  /// longer than one `pump()` and advances past it with `pump(duration)`.
  Duration latency = Duration.zero;

  @override
  Future<AnkiSettings> loadAnkiSettings() async {
    await _yield();
    return stored ?? AnkiSettings.defaults;
  }

  @override
  Future<void> saveAnkiSettings(AnkiSettings settings) async {
    await _yield();
    stored = settings;
    saved.add(settings);
  }

  @override
  Future<bool> loadSaveCrops() async {
    await _yield(saveCropsFailure);
    return saveCrops;
  }

  @override
  Future<void> saveSaveCrops(bool value) async {
    await _yield(saveCropsFailure);
    saveCrops = value;
    savedSaveCrops.add(value);
  }

  @override
  Future<bool> loadTranslateEnabled() async {
    await _yield(translateEnabledFailure);
    return translateEnabled;
  }

  @override
  Future<void> saveTranslateEnabled(bool value) async {
    await _yield(translateEnabledFailure);
    translateEnabled = value;
    savedTranslateEnabled.add(value);
  }

  @override
  Future<bool> loadKeepAwake() async {
    await _settle();
    return keepAwake;
  }

  @override
  Future<void> saveKeepAwake(bool value) async {
    await _settle();
    keepAwake = value;
    savedKeepAwake.add(value);
  }

  Future<void> _settle() async {
    final f = failure ?? keepAwakeFailure;
    await Future<void>.value();
    if (f != null) throw f;
  }

  Future<void> _yield([Exception? also]) async {
    final f = failure ?? also;
    await Future<void>.delayed(latency);
    if (f != null) throw f;
  }
}
