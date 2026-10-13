import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/ui/settings/view/settings_view.dart';
import 'package:yomitanuki/ui/settings/view_model/settings_view_model.dart';

import '../../../fakes/fake_settings_repository.dart';

void main() {
  Future<SettingsViewModel> pumpSettings(
    WidgetTester tester,
    FakeSettingsRepository repo, {
    ThemeData? theme,
  }) async {
    final vm = SettingsViewModel(repository: repo);
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

  testWidgets('a failed save is shown, the edit stays', (tester) async {
    final repo = FakeSettingsRepository();
    await pumpSettings(tester, repo);
    repo.failure = Exception('disk full');

    await tester.enterText(find.byKey(SettingsView.deckKey), 'X');
    await tester.pump();

    expect(find.textContaining('disk full'), findsOneWidget);
    expect(textOf(tester, SettingsView.deckKey), 'X');
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
}
