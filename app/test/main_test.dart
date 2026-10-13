import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/main.dart';
import 'package:yomitanuki/ui/reader/view/reader_view.dart';

import 'fakes/fake_anki_exporter.dart';
import 'fakes/fake_dictionary.dart';
import 'fakes/fake_frame_source.dart';
import 'fakes/fake_ocr_engine.dart';
import 'fakes/fake_photo_picker.dart';
import 'fakes/fake_text_detector.dart';

AppDependencies fakes() => AppDependencies(
  frameSource: FakeFrameSource(),
  cameraPreview: (_) => const SizedBox.shrink(),
  photoPicker: FakePhotoPicker(),
  detector: FakeTextDetector(),
  ocr: FakeOcrEngine(),
  dictionary: FakeDictionary(),
  anki: FakeAnkiExporter(),
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

  testWidgets('a route another branch provides is reported, not crashed on', (
    tester,
  ) async {
    await tester.pumpWidget(YomitanukiApp(dependencies: fakes()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader.settings')));
    await tester.pumpAndSettle();

    expect(find.textContaining('settings'), findsWidgets);
    expect(find.textContaining('not available'), findsOneWidget);
  });

  testWidgets('the production wiring constructs without touching a plugin', (
    tester,
  ) async {
    final deps = AppDependencies.production();

    expect(deps.detector, isNotNull);
    expect(deps.dictionary, isNotNull);
    expect(deps.anki, isNotNull);
  });
}
