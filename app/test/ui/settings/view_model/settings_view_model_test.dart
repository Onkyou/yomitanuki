import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/translation_status.dart';
import 'package:yomitanuki/ui/settings/view_model/settings_view_model.dart';

import '../../../fakes/fake_sentence_translator.dart';
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
    final vm = SettingsViewModel(
      repository: repo,
      translator: FakeSentenceTranslator(),
    );
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
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
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

  test('the sentence note type is saved like the note type, and reset '
      'clears it', () async {
    final repo = FakeSettingsRepository();
    final vm = SettingsViewModel(
      repository: repo,
      translator: FakeSentenceTranslator(),
    );
    await vm.load();

    await vm.setSentenceNoteType('Frieren Sentences');

    expect(repo.saved.last.sentenceNoteType, 'Frieren Sentences');
    expect(vm.settings?.sentenceNoteType, 'Frieren Sentences');
    expect(vm.error, isNull);

    await vm.setSentenceNoteType('');
    expect(vm.error, isNull);
    expect(repo.saved.last.problems, isEmpty);

    await vm.setSentenceNoteType('Again');
    await vm.resetToDefaults();
    expect(vm.settings?.sentenceNoteType, isNull);
    expect(repo.stored, AnkiSettings.defaults);
  });

  test('a successful edit notifies once, before the save lands', () async {
    final repo = FakeSettingsRepository();
    final vm = SettingsViewModel(
      repository: repo,
      translator: FakeSentenceTranslator(),
    );
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
    final vm = SettingsViewModel(
      repository: repo,
      translator: FakeSentenceTranslator(),
    );
    await vm.load();

    await vm.resetToDefaults();

    expect(vm.settings, AnkiSettings.defaults);
    expect(repo.stored, AnkiSettings.defaults);
  });

  test(
    'a failed save keeps the edit, reports a fixed sentence, notifies twice',
    () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
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
    final vm = SettingsViewModel(
      repository: repo,
      translator: FakeSentenceTranslator(),
    );
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
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );

      await vm.load();

      expect(vm.settings, AnkiSettings.defaults);
      expect(vm.error, 'Settings could not be loaded.');
      expect(vm.lastFailure.toString(), contains('corrupt'));
    },
  );

  group('validation (D5.8)', () {
    test('an invalid edit is shown and reported but not saved', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
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
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
      await vm.load();

      await vm.setFieldName(AnkiField.reading, 'Word');

      expect(vm.error, 'The field name "Word" is used twice.');
      expect(repo.saved, isEmpty);
    });

    test('the next valid edit saves and clears the error', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
      await vm.load();
      await vm.setDeck('');

      await vm.setDeck('Japanese::Vol. 3');

      expect(vm.error, isNull);
      expect(repo.saved.single.deck, 'Japanese::Vol. 3');
    });
  });

  group('save crops (D6a.4)', () {
    test(
      'load exposes the stored switch, off by default, in one notification',
      () async {
        final off = SettingsViewModel(
          repository: FakeSettingsRepository(),
          translator: FakeSentenceTranslator(),
        );
        await off.load();
        expect(off.saveCrops, isFalse);

        final repo = FakeSettingsRepository()..saveCrops = true;
        final on = SettingsViewModel(
          repository: repo,
          translator: FakeSentenceTranslator(),
        );
        final notifications = countNotifications(on);
        await on.load();

        expect(on.saveCrops, isTrue);
        expect(notifications(), 1);
      },
    );

    test('setSaveCrops shows the switch at once and saves it', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
      await vm.load();
      final notifications = countNotifications(vm);

      final pending = vm.setSaveCrops(true);

      expect(vm.saveCrops, isTrue);
      expect(notifications(), 1);
      await pending;
      expect(repo.savedSaveCrops, [true]);
      expect(repo.saved, isEmpty, reason: 'Anki settings are not rewritten');
      expect(vm.error, isNull);
    });

    test('a failed save keeps the switch on screen and reports', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
      await vm.load();
      repo.failure = Exception('disk full');

      await vm.setSaveCrops(true);

      expect(vm.saveCrops, isTrue);
      expect(vm.error, 'Settings could not be saved.');
    });

    test(
      'a failing crops load keeps the Anki settings that did load',
      () async {
        final repo = FakeSettingsRepository(stored: stored)
          ..saveCropsFailure = Exception('corrupt flag');
        final vm = SettingsViewModel(
          repository: repo,
          translator: FakeSentenceTranslator(),
        );

        await vm.load();

        expect(vm.settings, stored, reason: 'not replaced by the defaults');
        expect(vm.saveCrops, isFalse);
        expect(vm.error, 'Settings could not be loaded.');
      },
    );

    test('a successful crops save clears a stale error (D5.7)', () async {
      final repo = FakeSettingsRepository();
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
      await vm.load();
      repo.saveCropsFailure = Exception('disk full');
      await vm.setSaveCrops(true);
      expect(vm.error, 'Settings could not be saved.');

      repo.saveCropsFailure = null;
      await vm.setSaveCrops(false);

      expect(vm.error, isNull);
      expect(repo.savedSaveCrops, [false]);
    });

    test('reset to defaults leaves the diagnostics switch alone', () async {
      final repo = FakeSettingsRepository()..saveCrops = true;
      final vm = SettingsViewModel(
        repository: repo,
        translator: FakeSentenceTranslator(),
      );
      await vm.load();

      await vm.resetToDefaults();

      expect(vm.saveCrops, isTrue);
    });
  });

  group('translate sentences (D6c.5)', () {
    SettingsViewModel make(
      FakeSettingsRepository repo, [
      FakeSentenceTranslator? translator,
    ]) => SettingsViewModel(
      repository: repo,
      translator: translator ?? FakeSentenceTranslator(),
    );

    test('load exposes the stored switch, on by default, in one '
        'notification', () async {
      final on = make(FakeSettingsRepository());
      expect(on.translateEnabled, isTrue, reason: 'on before load, too');
      await on.load();
      expect(on.translateEnabled, isTrue);

      final repo = FakeSettingsRepository()..translateEnabled = false;
      final off = make(repo);
      final notifications = countNotifications(off);
      await off.load();

      expect(off.translateEnabled, isFalse);
      expect(notifications(), 1);
    });

    test('setTranslateEnabled shows the switch at once and saves it', () async {
      final repo = FakeSettingsRepository();
      final vm = make(repo);
      await vm.load();
      final notifications = countNotifications(vm);

      final pending = vm.setTranslateEnabled(false);

      expect(vm.translateEnabled, isFalse);
      expect(notifications(), 1);
      await pending;
      expect(repo.savedTranslateEnabled, [false]);
      expect(repo.saved, isEmpty, reason: 'Anki settings are not rewritten');
      expect(vm.error, isNull);
    });

    test('a failed save keeps the switch on screen and reports', () async {
      final repo = FakeSettingsRepository();
      final vm = make(repo);
      await vm.load();
      repo.translateEnabledFailure = Exception('disk full');

      await vm.setTranslateEnabled(false);

      expect(vm.translateEnabled, isFalse);
      expect(vm.error, 'Settings could not be saved.');
    });

    test('a successful save clears a stale error (D5.7)', () async {
      final repo = FakeSettingsRepository();
      final vm = make(repo);
      await vm.load();
      repo.translateEnabledFailure = Exception('disk full');
      await vm.setTranslateEnabled(false);
      expect(vm.error, 'Settings could not be saved.');

      repo.translateEnabledFailure = null;
      await vm.setTranslateEnabled(true);

      expect(vm.error, isNull);
    });

    test(
      'a failing switch load keeps the Anki settings that did load',
      () async {
        final repo = FakeSettingsRepository(stored: stored)
          ..translateEnabledFailure = Exception('corrupt flag');
        final vm = make(repo);

        await vm.load();

        expect(vm.settings, stored, reason: 'not replaced by the defaults');
        expect(vm.translateEnabled, isTrue);
        expect(vm.error, 'Settings could not be loaded.');
      },
    );

    test('the status text follows the translator, per status', () async {
      const expected = {
        TranslationStatus.installed:
            'Japanese → English is installed for offline use.',
        TranslationStatus.downloadNeeded:
            'Download Japanese and English under Settings › Apps › '
            'Translate › Downloaded Languages to translate offline.',
        TranslationStatus.unsupported:
            'This device cannot translate Japanese to English.',
        TranslationStatus.requiresNewerOs: 'Sentence translation needs iOS 26.',
      };
      for (final MapEntry(key: status, value: text) in expected.entries) {
        final vm = make(
          FakeSettingsRepository(),
          FakeSentenceTranslator(reported: status),
        );
        expect(vm.translationStatusText, '', reason: 'before load');

        await vm.load();

        expect(vm.translationStatus, status);
        expect(vm.translationStatusText, text);
      }
    });

    test(
      'a failing status query leaves the text empty and the rest loaded',
      () async {
        final repo = FakeSettingsRepository(stored: stored);
        final vm = make(
          repo,
          FakeSentenceTranslator(statusError: Exception('channel gone')),
        );

        await vm.load();

        expect(vm.translationStatus, isNull);
        expect(vm.translationStatusText, '');
        expect(vm.settings, stored);
        expect(vm.translateEnabled, isTrue);
      },
    );

    test('reset to defaults leaves the switch alone', () async {
      final repo = FakeSettingsRepository()..translateEnabled = false;
      final vm = make(repo);
      await vm.load();

      await vm.resetToDefaults();

      expect(vm.translateEnabled, isFalse);
    });
  });
}
