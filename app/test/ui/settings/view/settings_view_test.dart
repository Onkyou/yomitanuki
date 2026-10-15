import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/translation_status.dart';
import 'package:yomitanuki/ui/settings/view/settings_view.dart';
import 'package:yomitanuki/ui/settings/view_model/settings_view_model.dart';

import '../../../fakes/fake_sentence_translator.dart';
import '../../../fakes/fake_settings_repository.dart';

void main() {
  Future<SettingsViewModel> pumpSettings(
    WidgetTester tester,
    FakeSettingsRepository repo, {
    ThemeData? theme,
    FakeSentenceTranslator? translator,
  }) async {
    final vm = SettingsViewModel(
      repository: repo,
      translator: translator ?? FakeSentenceTranslator(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: SettingsView(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).controller!.text;

  testWidgets('shows the defaults when nothing is stored', (tester) async {
    await pumpSettings(tester, FakeSettingsRepository());

    expect(find.text('Settings'), findsOneWidget);
    expect(textOf(tester, SettingsView.deckKey), 'Japanese::Frieren Vol. 1');
    expect(textOf(tester, SettingsView.noteTypeKey), 'Frieren Vocab (JP→EN)');
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.word)), 'Word');
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.reading)), 'Reading');
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.meaning)), 'Meaning');
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.example)), 'Example');
    expect(
      textOf(tester, SettingsView.fieldKey(AnkiField.exampleEn)),
      'ExampleEN',
    );
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.note)), 'Note');
  });

  testWidgets('shows stored settings', (tester) async {
    final stored = AnkiSettings.defaults
        .copyWith(deck: 'Japanese::Vol. 2')
        .withFieldName(AnkiField.note, 'Notes');

    await pumpSettings(tester, FakeSettingsRepository(stored: stored));

    expect(textOf(tester, SettingsView.deckKey), 'Japanese::Vol. 2');
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.note)), 'Notes');
  });

  testWidgets('editing a field saves through the repository', (tester) async {
    final repo = FakeSettingsRepository();
    await pumpSettings(tester, repo);

    await tester.enterText(
      find.byKey(SettingsView.deckKey),
      'Japanese::Frieren Vol. 2',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(SettingsView.fieldKey(AnkiField.exampleEn)),
      'Translation',
    );
    await tester.pump();

    expect(repo.stored?.deck, 'Japanese::Frieren Vol. 2');
    expect(repo.stored?.fieldName(AnkiField.exampleEn), 'Translation');
    expect(repo.stored?.noteType, 'Frieren Vocab (JP→EN)');
  });

  testWidgets('Reset to defaults restores every field and saves', (
    tester,
  ) async {
    final repo = FakeSettingsRepository(
      stored: AnkiSettings.defaults
          .copyWith(deck: 'Japanese::Vol. 2', noteType: 'Basic')
          .withFieldName(AnkiField.word, 'Front'),
    );
    await pumpSettings(tester, repo);
    expect(textOf(tester, SettingsView.deckKey), 'Japanese::Vol. 2');

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();

    expect(textOf(tester, SettingsView.deckKey), 'Japanese::Frieren Vol. 1');
    expect(textOf(tester, SettingsView.noteTypeKey), 'Frieren Vocab (JP→EN)');
    expect(textOf(tester, SettingsView.fieldKey(AnkiField.word)), 'Word');
    expect(repo.stored, AnkiSettings.defaults);
  });

  testWidgets('a failed save is shown once the save lands, the edit stays', (
    tester,
  ) async {
    final repo = FakeSettingsRepository()
      ..latency = const Duration(milliseconds: 50);
    await pumpSettings(tester, repo);
    repo.failure = Exception('disk full');

    await tester.enterText(find.byKey(SettingsView.deckKey), 'X');
    await tester.pump();
    // The edit is on screen before the save answers; the banner is not.
    expect(textOf(tester, SettingsView.deckKey), 'X');
    expect(find.text('Settings could not be saved.'), findsNothing);

    // The save fails; only the view model's second notification can bring
    // the banner into this frame.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Settings could not be saved.'), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(textOf(tester, SettingsView.deckKey), 'X');
  });

  testWidgets('an invalid edit shows the problem and stays editable', (
    tester,
  ) async {
    final repo = FakeSettingsRepository();
    await pumpSettings(tester, repo);

    await tester.enterText(find.byKey(SettingsView.deckKey), '');
    await tester.pump();

    expect(find.text('Deck must not be empty.'), findsOneWidget);
    expect(repo.saved, isEmpty);

    await tester.enterText(find.byKey(SettingsView.deckKey), 'Japanese');
    await tester.pumpAndSettle();

    expect(find.text('Deck must not be empty.'), findsNothing);
    expect(repo.stored?.deck, 'Japanese');
  });

  testWidgets('typing keeps the caret at the end of the edit (D5.7)', (
    tester,
  ) async {
    await pumpSettings(tester, FakeSettingsRepository());
    final deck = find.byKey(SettingsView.deckKey);

    await tester.enterText(deck, 'Japanese::Vol. 2');
    await tester.pump();
    await tester.pump();

    final controller = tester.widget<TextField>(deck).controller!;
    expect(controller.text, 'Japanese::Vol. 2');
    expect(
      controller.selection,
      const TextSelection.collapsed(offset: 'Japanese::Vol. 2'.length),
    );
  });

  testWidgets('renders in the dark theme too', (tester) async {
    await pumpSettings(
      tester,
      FakeSettingsRepository(),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.brown,
      ),
    );

    expect(find.text('Reset to defaults'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Diagnostics switch is off by default and saves when '
      'toggled', (tester) async {
    final repo = FakeSettingsRepository();
    await pumpSettings(tester, repo);
    final toggle = find.byKey(SettingsView.saveCropsKey);
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Save OCR crops'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(repo.savedSaveCrops, [true]);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('the Diagnostics switch shows the stored value', (tester) async {
    await pumpSettings(tester, FakeSettingsRepository()..saveCrops = true);
    final toggle = find.byKey(SettingsView.saveCropsKey);
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  group('the Reading section (D6c.5)', () {
    testWidgets('Translate sentences is on by default with the status as its '
        'subtitle, and saves when toggled', (tester) async {
      final repo = FakeSettingsRepository();
      await pumpSettings(tester, repo);
      final toggle = find.byKey(SettingsView.translateKey);

      expect(find.byKey(SettingsView.readingSectionKey), findsOneWidget);
      expect(find.text('Translate sentences'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(
        find.text('Japanese → English is installed for offline use.'),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(repo.savedTranslateEnabled, [false]);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    });

    testWidgets('shows the stored value', (tester) async {
      await pumpSettings(
        tester,
        FakeSettingsRepository()..translateEnabled = false,
      );

      expect(
        tester
            .widget<SwitchListTile>(find.byKey(SettingsView.translateKey))
            .value,
        isFalse,
      );
    });

    testWidgets('the subtitle says where to download the packs', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        FakeSettingsRepository(),
        translator: FakeSentenceTranslator(
          reported: TranslationStatus.downloadNeeded,
        ),
      );

      expect(find.textContaining('Downloaded Languages'), findsOneWidget);
    });

    testWidgets('the section comes before Anki', (tester) async {
      await pumpSettings(tester, FakeSettingsRepository());

      expect(
        tester.getTopLeft(find.byKey(SettingsView.readingSectionKey)).dy,
        lessThan(tester.getTopLeft(find.byKey(SettingsView.deckKey)).dy),
      );
    });
  });
}
