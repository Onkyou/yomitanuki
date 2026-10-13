import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/ui/settings/view_model/settings_view_model.dart';

import '../../../fakes/fake_settings_repository.dart';

void main() {
  final stored = AnkiSettings.defaults
      .copyWith(deck: 'Japanese::Vol. 2')
      .withFieldName(AnkiField.note, 'Notes');

  test('load exposes what the repository holds and notifies once', () async {
    final repo = FakeSettingsRepository(stored: stored);
    final vm = SettingsViewModel(repository: repo);
    var notifications = 0;
    vm.addListener(() => notifications++);

    expect(vm.settings, isNull);
    await vm.load();

    expect(vm.settings, stored);
    expect(vm.error, isNull);
    expect(notifications, 1);
  });

  test(
    'each edit saves the whole settings object through the repository',
    () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(repository: repo);
      await vm.load();

      await vm.setDeck('Japanese::Vol. 3');
      await vm.setNoteType('Basic');
      await vm.setFieldName(AnkiField.exampleEn, 'Translation');

      expect(repo.saved, hasLength(3));
      expect(repo.saved.last.deck, 'Japanese::Vol. 3');
      expect(repo.saved.last.noteType, 'Basic');
      expect(repo.saved.last.fieldName(AnkiField.exampleEn), 'Translation');
      expect(vm.settings, repo.saved.last);
    },
  );

  test('resetToDefaults restores and saves the defaults', () async {
    final repo = FakeSettingsRepository(stored: stored);
    final vm = SettingsViewModel(repository: repo);
    await vm.load();

    await vm.resetToDefaults();

    expect(vm.settings, AnkiSettings.defaults);
    expect(repo.stored, AnkiSettings.defaults);
  });

  test(
    'a failed save keeps the edit on screen and reports the error',
    () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(repository: repo);
      await vm.load();
      repo.failure = Exception('disk full');

      await vm.setDeck('Japanese::Vol. 3');

      expect(vm.settings?.deck, 'Japanese::Vol. 3');
      expect(vm.error, contains('disk full'));
      expect(repo.saved, isEmpty);

      repo.failure = null;
      await vm.setDeck('Japanese::Vol. 4');

      expect(vm.error, isNull);
      expect(repo.saved.single.deck, 'Japanese::Vol. 4');
    },
  );

  test(
    'a failed load falls back to the defaults and reports the error',
    () async {
      final repo = FakeSettingsRepository()..failure = Exception('corrupt');
      final vm = SettingsViewModel(repository: repo);

      await vm.load();

      expect(vm.settings, AnkiSettings.defaults);
      expect(vm.error, contains('corrupt'));
    },
  );
}
