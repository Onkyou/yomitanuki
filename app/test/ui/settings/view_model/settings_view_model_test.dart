import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/ui/settings/view_model/settings_view_model.dart';

import '../../../fakes/fake_settings_repository.dart';

void main() {
  final stored = AnkiSettings.defaults
      .copyWith(deck: 'Japanese::Vol. 2')
      .withFieldName(AnkiField.note, 'Notes');

  int Function() countNotifications(SettingsViewModel vm) {
    var n = 0;
    vm.addListener(() => n++);
    return () => n;
  }

  test('load exposes what the repository holds and notifies once', () async {
    final repo = FakeSettingsRepository(stored: stored);
    final vm = SettingsViewModel(repository: repo);
    final notifications = countNotifications(vm);

    expect(vm.settings, isNull);
    await vm.load();

    expect(vm.settings, stored);
    expect(vm.error, isNull);
    expect(notifications(), 1);
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

  test('a successful edit notifies once, before the save lands', () async {
    final repo = FakeSettingsRepository();
    final vm = SettingsViewModel(repository: repo);
    await vm.load();
    final notifications = countNotifications(vm);

    final pending = vm.setDeck('Japanese::Vol. 3');

    expect(vm.settings?.deck, 'Japanese::Vol. 3');
    expect(notifications(), 1);
    expect(repo.saved, isEmpty);
    await pending;
    expect(repo.saved, hasLength(1));
    expect(notifications(), 1);
  });

  test('resetToDefaults restores and saves the defaults', () async {
    final repo = FakeSettingsRepository(stored: stored);
    final vm = SettingsViewModel(repository: repo);
    await vm.load();

    await vm.resetToDefaults();

    expect(vm.settings, AnkiSettings.defaults);
    expect(repo.stored, AnkiSettings.defaults);
  });

  test(
    'a failed save keeps the edit, reports a fixed sentence, notifies twice',
    () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(repository: repo);
      await vm.load();
      final notifications = countNotifications(vm);
      repo.failure = Exception('disk full');

      await vm.setDeck('Japanese::Vol. 3');

      expect(vm.settings?.deck, 'Japanese::Vol. 3');
      expect(vm.error, 'Settings could not be saved.');
      expect(vm.lastFailure.toString(), contains('disk full'));
      expect(repo.saved, isEmpty);
      expect(notifications(), 2);

      repo.failure = null;
      await vm.setDeck('Japanese::Vol. 4');

      expect(vm.error, isNull);
      expect(vm.lastFailure, isNull);
      expect(repo.saved.single.deck, 'Japanese::Vol. 4');
      expect(notifications(), 4, reason: 'state, then the cleared error');
    },
  );

  test('a save that fails after a newer edit does not report (D5.7)', () async {
    final repo = FakeSettingsRepository();
    final vm = SettingsViewModel(repository: repo);
    await vm.load();
    final notifications = countNotifications(vm);

    repo.failure = Exception('disk full');
    final stale = vm.setDeck('Japanese::Vol. 3');
    repo.failure = null;
    final fresh = vm.setDeck('Japanese::Vol. 4');
    await Future.wait([stale, fresh]);

    expect(vm.settings?.deck, 'Japanese::Vol. 4');
    expect(vm.error, isNull);
    expect(repo.saved.single.deck, 'Japanese::Vol. 4');
    expect(notifications(), 2);
  });

  test(
    'a failed load falls back to the defaults and reports the error',
    () async {
      final repo = FakeSettingsRepository()..failure = Exception('corrupt');
      final vm = SettingsViewModel(repository: repo);

      await vm.load();

      expect(vm.settings, AnkiSettings.defaults);
      expect(vm.error, 'Settings could not be loaded.');
      expect(vm.lastFailure.toString(), contains('corrupt'));
    },
  );

  group('validation (D5.8)', () {
    test('an invalid edit is shown and reported but not saved', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(repository: repo);
      await vm.load();
      final notifications = countNotifications(vm);

      await vm.setDeck('   ');

      expect(vm.settings?.deck, '   ');
      expect(vm.error, 'Deck must not be empty.');
      expect(repo.saved, isEmpty);
      expect(notifications(), 1);
    });

    test('a duplicate field name lists the name', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(repository: repo);
      await vm.load();

      await vm.setFieldName(AnkiField.reading, 'Word');

      expect(vm.error, 'The field name "Word" is used twice.');
      expect(repo.saved, isEmpty);
    });

    test('the next valid edit saves and clears the error', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(repository: repo);
      await vm.load();
      await vm.setDeck('');

      await vm.setDeck('Japanese::Vol. 3');

      expect(vm.error, isNull);
      expect(repo.saved.single.deck, 'Japanese::Vol. 3');
    });
  });
}
