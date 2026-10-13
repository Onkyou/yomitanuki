import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/ui/about/view/about_view.dart';
import 'package:yomitanuki/ui/reader/view/block_overlay.dart';
import 'package:yomitanuki/ui/reader/view/reader_view.dart';
import 'package:yomitanuki/ui/reader/view_model/frame_mapping.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_view_model.dart';

import '../../../fakes/fake_anki_exporter.dart';
import '../../../fakes/fake_dictionary.dart';
import '../../../fakes/fake_frame_source.dart';
import '../../../fakes/fake_ocr_engine.dart';
import '../../../fakes/fake_photo_picker.dart';
import '../../../fakes/fake_settings_repository.dart';
import '../../../fakes/fake_text_detector.dart';
import '../../../fakes/images.dart';

const block = TextBlock(box: Rect.fromLTWH(10, 10, 20, 20), confidence: 0.9);

class Harness {
  Harness() {
    viewModel = ReaderViewModel(
      frameSource: frames,
      photoPicker: photos,
      detector: detector,
      ocr: ocr,
      dictionary: dictionary,
      anki: anki,
      settings: settings,
      clock: () => now,
    );
  }

  /// The view model's clock, advanced by hand (DateTime.now is not faked by
  /// the test binding).
  DateTime now = DateTime.utc(2026, 10, 13);
  final frames = FakeFrameSource();
  final settings = FakeSettingsRepository();
  final photos = FakePhotoPicker();
  final detector = FakeTextDetector(blocks: const [block]);
  final ocr = FakeOcrEngine(text: '食べられなかった');
  final dictionary = FakeDictionary(
    results: [taberareNakattaResult],
    kanjiEntries: {'食': shokuKanji},
  );
  final anki = FakeAnkiExporter();
  late final ReaderViewModel viewModel;

  /// The about route is registered because the reader pushes it by name,
  /// as YomitanukiApp does in main.dart.
  Widget app({Map<String, WidgetBuilder> routes = const {}}) => MaterialApp(
    routes: {'about': (_) => const AboutView(), ...routes},
    home: ReaderView(
      viewModel: viewModel,
      cameraPreview: const ColoredBox(
        key: Key('test.preview'),
        color: Colors.black,
      ),
    ),
  );

  /// Pumps the reader, delivers one 100x100 frame and lets detection finish.
  Future<void> pumpWithFrame(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    frames.emit(testImage(100, 100));
    await tester.pump();
  }

  /// Taps the centre of [block] where the overlay draws it.
  Future<void> tapBlock(WidgetTester tester) async {
    final overlay = find.byKey(const Key('reader.overlay'));
    final mapping = FrameMapping.cover(
      frame: const Size(100, 100),
      preview: tester.getSize(overlay),
    );
    final local = mapping.toPreviewPoint(block.box.center);
    await tester.tapAt(tester.getTopLeft(overlay) + local);
    await tester.pump();
  }

  Future<void> openSheetAndLookup(WidgetTester tester) async {
    await pumpWithFrame(tester);
    await tapBlock(tester);
    await tester.tap(find.byKey(const Key('ocr.char.0')));
    await tester.pump();
  }
}

BlockOverlayPainter overlayPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const Key('reader.overlay')),
  );
  return paint.painter! as BlockOverlayPainter;
}

void main() {
  testWidgets('starts the camera and shows the injected preview', (
    tester,
  ) async {
    final h = Harness();

    await tester.pumpWidget(h.app());
    await tester.pump();

    expect(h.frames.startCalls, 1);
    expect(find.byKey(const Key('test.preview')), findsOneWidget);
  });

  testWidgets('draws one rounded box per detected block', (tester) async {
    final h = Harness();

    await h.pumpWithFrame(tester);

    final painter = overlayPainter(tester);
    expect(painter.boxes, hasLength(1));
    final expected = FrameMapping.cover(
      frame: const Size(100, 100),
      preview: tester.getSize(find.byKey(const Key('reader.overlay'))),
    ).toPreview(block.box);
    expect(painter.boxes.single, expected);
  });

  testWidgets('shows a scanning indicator while detection is in flight', (
    tester,
  ) async {
    final h = Harness();
    h.detector.hold();
    await tester.pumpWidget(h.app());
    await tester.pump();

    h.frames.emit(testImage(100, 100));
    await tester.pump();
    expect(find.byKey(const Key('reader.scanning')), findsOneWidget);

    h.detector.release();
    await tester.pump();
    expect(find.byKey(const Key('reader.scanning')), findsNothing);
  });

  testWidgets('tapping a box opens the sheet with each character tappable', (
    tester,
  ) async {
    final h = Harness();
    await h.pumpWithFrame(tester);

    await h.tapBlock(tester);

    expect(h.ocr.crops, hasLength(1));
    expect(find.byKey(const Key('ocr.char.0')), findsOneWidget);
    expect(find.byKey(const Key('ocr.char.7')), findsOneWidget);
    expect(find.text('食'), findsOneWidget);
    expect(find.text('た'), findsOneWidget);
  });

  testWidgets('tapping outside every box does nothing', (tester) async {
    final h = Harness();
    await h.pumpWithFrame(tester);

    final overlay = find.byKey(const Key('reader.overlay'));
    await tester.tapAt(tester.getBottomRight(overlay) - const Offset(2, 2));
    await tester.pump();

    expect(h.ocr.crops, isEmpty);
    expect(find.byKey(const Key('ocr.sheet')), findsNothing);
  });

  testWidgets('tapping a character shows the entry with reading, glosses, '
      'deinflection chips and kanji breakdown', (tester) async {
    final h = Harness();

    await h.openSheetAndLookup(tester);

    expect(h.dictionary.lookups, [('食べられなかった', 0)]);
    expect(find.text('食べる'), findsOneWidget);
    expect(find.text('たべる'), findsOneWidget);
    expect(find.textContaining('to eat'), findsOneWidget);
    expect(find.text('past'), findsOneWidget);
    expect(find.text('potential'), findsOneWidget);
    expect(find.textContaining('eat, food'), findsOneWidget);
    expect(find.byKey(const Key('anki.add.0')), findsOneWidget);
  });

  testWidgets('no match says so instead of showing an empty list', (
    tester,
  ) async {
    final h = Harness();
    h.dictionary.results = [];

    await h.openSheetAndLookup(tester);

    expect(find.byKey(const Key('lookup.empty')), findsOneWidget);
  });

  testWidgets('Add to Anki shows the hand-over as a snackbar', (tester) async {
    final h = Harness();
    await h.openSheetAndLookup(tester);

    await tester.tap(find.byKey(const Key('anki.add.0')));
    await tester.pumpAndSettle();

    expect(h.anki.notes.single.fields['Example'], '食べられなかった');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('AnkiMobile'), findsOneWidget);
    expect(h.viewModel.ankiMessage, isNull, reason: 'consumed once shown');
  });

  testWidgets('Add to Anki reports a missing AnkiMobile', (tester) async {
    final h = Harness();
    h.anki.outcome = AnkiExportOutcome.ankiNotInstalled;
    await h.openSheetAndLookup(tester);

    await tester.tap(find.byKey(const Key('anki.add.0')));
    await tester.pumpAndSettle();

    expect(find.textContaining('not installed'), findsOneWidget);
  });

  testWidgets('closing the sheet returns to the live view', (tester) async {
    final h = Harness();
    await h.pumpWithFrame(tester);
    await h.tapBlock(tester);

    await tester.tap(find.byKey(const Key('ocr.close')));
    await tester.pump();

    expect(find.byKey(const Key('ocr.sheet')), findsNothing);
  });

  testWidgets('an OCR failure is shown in the sheet', (tester) async {
    final h = Harness();
    h.ocr.error = NotWiredError('OcrEngine');
    await h.pumpWithFrame(tester);

    await h.tapBlock(tester);

    expect(find.textContaining('OcrEngine'), findsOneWidget);
  });

  testWidgets('a detector failure is shown as a banner', (tester) async {
    final h = Harness();
    h.detector.error = NotWiredError('TextDetector');

    await h.pumpWithFrame(tester);

    expect(find.textContaining('TextDetector'), findsOneWidget);
  });

  testWidgets('a denied camera permission is explained with a retry', (
    tester,
  ) async {
    final h = Harness();
    h.frames.startError = const CameraPermissionDeniedError();

    await tester.pumpWidget(h.app());
    await tester.pump();

    expect(find.textContaining('Camera access'), findsOneWidget);
    expect(find.byKey(const Key('reader.retry')), findsOneWidget);
  });

  testWidgets('the photo action detects on the picked photo and offers '
      'a way back to the camera', (tester) async {
    final h = Harness();
    h.photos.photo = testImage(40, 60, seed: 7);
    await h.pumpWithFrame(tester);

    await tester.tap(find.byKey(const Key('reader.pickPhoto')));
    await tester.pump();

    expect(h.detector.calls.last.bytes[2], 7);
    expect(overlayPainter(tester).boxes, hasLength(1));
    expect(find.byKey(const Key('test.preview')), findsNothing);

    await tester.tap(find.byKey(const Key('reader.backToCamera')));
    await tester.pump();

    expect(find.byKey(const Key('test.preview')), findsOneWidget);
    expect(h.frames.startCalls, 2);
  });

  testWidgets('the sheet shows the reading state and then the text once '
      'OCR finishes', (tester) async {
    final h = Harness();
    h.ocr.hold();
    await h.pumpWithFrame(tester);

    await h.tapBlock(tester);
    expect(find.textContaining('Reading'), findsOneWidget);
    expect(find.byKey(const Key('ocr.char.0')), findsNothing);

    h.ocr.release();
    await tester.pump();

    expect(find.byKey(const Key('ocr.char.0')), findsOneWidget);
    expect(find.textContaining('Reading'), findsNothing);
  });

  testWidgets('three empty detections show the no-bubbles hint', (
    tester,
  ) async {
    final h = Harness();
    h.detector.blocks = const [];
    await tester.pumpWidget(h.app());
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      h.frames.emit(testImage(100, 100));
      await tester.pump();
      h.now = h.now.add(const Duration(seconds: 1));
    }

    expect(find.byKey(const Key('reader.noBlocks')), findsOneWidget);
    expect(find.textContaining('No bubbles found'), findsOneWidget);
  });

  testWidgets('the notice banner can be dismissed', (tester) async {
    final h = Harness();
    h.detector.error = NotWiredError('TextDetector');
    await h.pumpWithFrame(tester);
    expect(find.textContaining('TextDetector'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader.notice.close')));
    await tester.pump();

    expect(find.textContaining('TextDetector'), findsNothing);
  });

  testWidgets('the settings action pushes the route named settings', (
    tester,
  ) async {
    final h = Harness();
    await tester.pumpWidget(
      h.app(
        routes: {'settings': (_) => const Scaffold(body: Text('WP5 settings'))},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader.settings')));
    await tester.pumpAndSettle();

    expect(find.text('WP5 settings'), findsOneWidget);
  });

  testWidgets('the about action opens the attribution screen', (tester) async {
    final h = Harness();
    await tester.pumpWidget(h.app());
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader.about')));
    await tester.pumpAndSettle();

    expect(find.textContaining('EDRDG'), findsOneWidget);
    expect(find.textContaining('manga-ocr'), findsWidgets);
    expect(find.textContaining('comic-text-detector'), findsWidgets);
  });
}
