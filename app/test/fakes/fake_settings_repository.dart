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

  /// When set, every call throws it, so error paths can be exercised.
  Exception? failure;

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

  Future<void> _yield() async {
    final f = failure;
    await Future<void>.delayed(latency);
    if (f != null) throw f;
  }
}
