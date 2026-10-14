import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:yomitanuki/main.dart';
import 'package:yomitanuki/ui/reader/view/reader_view.dart';
import 'package:yomitanuki/ui/settings/view/settings_view.dart';

import 'fakes/fake_anki_exporter.dart';
import 'fakes/fake_dictionary.dart';
import 'fakes/fake_frame_source.dart';
import 'fakes/fake_ocr_capture_log.dart';
import 'fakes/fake_ocr_engine.dart';
import 'fakes/fake_photo_picker.dart';
import 'fakes/fake_settings_repository.dart';
import 'fakes/fake_text_detector.dart';

AppDependencies fakes() => AppDependencies(
  frameSource: FakeFrameSource(),
  cameraPreview: (_) => const SizedBox.shrink(),
  photoPicker: FakePhotoPicker(),
  detector: FakeTextDetector(),
  ocr: FakeOcrEngine(),
  dictionary: FakeDictionary(),
  anki: FakeAnkiExporter(),
  settingsRepository: FakeSettingsRepository(),
  captureLog: FakeOcrCaptureLog(),
);

void main() {
  testWidgets('YomitanukiApp opens on the reader', (tester) async {
    await tester.pumpWidget(YomitanukiApp(dependencies: fakes()));
    await tester.pump();

    expect(find.byType(ReaderView), findsOneWidget);
    expect(find.text('Yomitanuki'), findsOneWidget);
  });

  testWidgets('light and dark themes are Material 3', (tester) async {
    await tester.pumpWidget(YomitanukiApp(dependencies: fakes()));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.useMaterial3, isTrue);
    expect(app.darkTheme!.brightness, Brightness.dark);
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('the settings action opens the WP5 settings screen', (
    tester,
  ) async {
    await tester.pumpWidget(YomitanukiApp(dependencies: fakes()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader.settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('a route this build lacks is reported, not crashed on', (
    tester,
  ) async {
    await tester.pumpWidget(YomitanukiApp(dependencies: fakes()));
    await tester.pump();

    final context = tester.element(find.byType(ReaderView));
    unawaited(Navigator.pushNamed(context, 'history'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('"history" screen is not available'),
      findsOneWidget,
    );
  });

  testWidgets('the production wiring constructs with only the preferences '
      'platform stubbed', (tester) async {
    // SharedPreferencesAsync() reads its platform instance at construction;
    // the camera, picker and url_launcher adapters are lazy.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final deps = AppDependencies.production();

    expect(deps.detector, isNotNull);
    expect(deps.dictionary, isNotNull);
    expect(deps.anki, isNotNull);
  });
}
