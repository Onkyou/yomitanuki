// The happy path on a real engine (iOS Simulator): boot the app with fakes
// for every port, deliver one synthetic frame, tap the box, tap a character,
// add the entry to Anki. Run with `make gate-integration` (needs a booted
// simulator; see the Makefile for why it is not part of `make gate`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/main.dart';
import 'package:yomitanuki/ui/reader/view_model/frame_mapping.dart';

import '../test/fakes/fake_anki_exporter.dart';
import '../test/fakes/fake_dictionary.dart';
import '../test/fakes/fake_frame_source.dart';
import '../test/fakes/fake_ocr_capture_log.dart';
import '../test/fakes/fake_ocr_engine.dart';
import '../test/fakes/fake_photo_picker.dart';
import '../test/fakes/fake_sentence_translator.dart';
import '../test/fakes/fake_settings_repository.dart';
import '../test/fakes/fake_text_detector.dart';
import '../test/fakes/images.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('frame -> box -> tap -> text -> lookup -> Anki', (tester) async {
    const block = TextBlock(
      box: Rect.fromLTWH(200, 400, 400, 300),
      confidence: 0.9,
    );
    final frames = FakeFrameSource();
    final anki = FakeAnkiExporter();
    final deps = AppDependencies(
      frameSource: frames,
      cameraPreview: (_) => const ColoredBox(color: Colors.black),
      photoPicker: FakePhotoPicker(),
      detector: FakeTextDetector(blocks: const [block]),
      ocr: FakeOcrEngine(text: '食べられなかった'),
      dictionary: FakeDictionary(
        results: [taberareNakattaResult],
        kanjiEntries: {'食': shokuKanji},
      ),
      anki: anki,
      settingsRepository: FakeSettingsRepository(),
      captureLog: FakeOcrCaptureLog(),
      translator: FakeSentenceTranslator(),
    );

    await tester.pumpWidget(YomitanukiApp(dependencies: deps));
    await tester.pumpAndSettle();
    expect(frames.startCalls, 1);

    // A synthetic 1080p portrait frame, the real stream's size (D0.12).
    frames.emit(testImage(1080, 1920));
    await tester.pumpAndSettle();

    final overlay = find.byKey(const Key('reader.overlay'));
    expect(overlay, findsOneWidget);
    final mapping = FrameMapping.cover(
      frame: const Size(1080, 1920),
      preview: tester.getSize(overlay),
    );
    await tester.tapAt(
      tester.getTopLeft(overlay) + mapping.toPreviewPoint(block.box.center),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ocr.sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr.char.0')));
    await tester.pumpAndSettle();

    expect(find.text('食べる'), findsOneWidget);
    expect(find.text('たべる'), findsOneWidget);
    // The longest match's button lives in the sheet's bottom bar (D6e.5).
    await tester.tap(find.byKey(const Key('anki.addWord')));
    await tester.pumpAndSettle();

    expect(anki.notes.single.fields['Word'], '食べる');
    expect(find.textContaining('AnkiMobile'), findsOneWidget);
  });
}
