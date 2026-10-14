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

  /// When set, every call throws it, so error paths can be exercised.
  Exception? failure;

  /// When set, only the two save-crops calls throw it: the Anki calls still
  /// answer, so a partial load can be exercised.
  Exception? saveCropsFailure;

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

  Future<void> _yield([Exception? also]) async {
    final f = failure ?? also;
    await Future<void>.delayed(latency);
    if (f != null) throw f;
  }
}
