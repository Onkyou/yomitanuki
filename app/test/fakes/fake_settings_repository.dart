import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/ports/settings_repository.dart';

/// In-memory [SettingsRepository]: what was saved is what loads next, and
/// every save is recorded so a test can assert on the sequence.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({this.stored});

  /// What [loadAnkiSettings] returns; `null` stands for "nothing stored yet".
  AnkiSettings? stored;

  /// Every argument [saveAnkiSettings] received, oldest first.
  final List<AnkiSettings> saved = [];

  /// When set, every call throws it, so error paths can be exercised.
  Exception? failure;

  @override
  Future<AnkiSettings> loadAnkiSettings() async {
    _maybeFail();
    return stored ?? AnkiSettings.defaults;
  }

  @override
  Future<void> saveAnkiSettings(AnkiSettings settings) async {
    _maybeFail();
    stored = settings;
    saved.add(settings);
  }

  void _maybeFail() {
    final f = failure;
    if (f != null) throw f;
  }
}
