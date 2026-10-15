// Screenshots of the reader for design review, taken on the iOS Simulator:
//
//   flutter drive --driver=test_driver/screenshots.dart \
//     --target=integration_test/screenshots_test.dart \
//     --dart-define=SCREENSHOTS=true -d <simulator>
//
// Real detector, OCR and dictionary (as in real_pipeline_test.dart), a fake
// camera that shows one rendered page, and a fake translator, because Apple's
// Translation framework does not run in the Simulator (WP6c). PNGs land in
// app/build/screenshots/ (gitignored). Not part of `make gate-integration`
// (`flutter test integration_test` cannot save screenshots): the test is
// skipped unless `--dart-define=SCREENSHOTS=true` is passed, as the drive
// command above must.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yomitanuki/data/services/dictionary/bundled_dictionary_asset.dart';
import 'package:yomitanuki/data/services/dictionary/lazy_dictionary.dart';
import 'package:yomitanuki/data/services/ort/lazy_inference.dart';
import 'package:yomitanuki/data/services/photo/photo_decoder.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/main.dart';
import 'package:yomitanuki/ui/reader/view_model/frame_mapping.dart';

import '../test/fakes/fake_anki_exporter.dart';
import '../test/fakes/fake_frame_source.dart';
import '../test/fakes/fake_ocr_capture_log.dart';
import '../test/fakes/fake_photo_picker.dart';
import '../test/fakes/fake_sentence_translator.dart';
import '../test/fakes/fake_settings_repository.dart';

const _frameSize = Size(1080, 1920);
const _bubbleCentre = Offset(540, 700);
const _bubbleText = '魔王を倒した勇者';
const _translation = 'The hero who defeated the Demon King.';

/// The same page as real_pipeline_test.dart: one vertical bubble on a panel.
Future<BgraImage> renderPage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _frameSize, Paint()..color = Colors.white);
  final ink = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5;
  canvas.drawRect(const Rect.fromLTWH(60, 60, 960, 1800), ink);
  final bubble = Rect.fromCenter(
    center: _bubbleCentre,
    width: 340,
    height: 620,
  );
  canvas.drawOval(bubble, Paint()..color = Colors.white);
  canvas.drawOval(bubble, ink);
  var y = _bubbleCentre.dy - 250;
  for (final rune in _bubbleText.runes) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(rune),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 56,
          fontFamily: 'Hiragino Sans',
          fontFamilyFallback: ['Hiragino Mincho ProN', 'Apple SD Gothic Neo'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(_bubbleCentre.dx - painter.width / 2, y));
    y += 62;
  }
  final image = await recorder.endRecording().toImage(
    _frameSize.width.toInt(),
    _frameSize.height.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return decodePhoto(png!.buffer.asUint8List());
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder,
  String what, {
  Duration timeout = const Duration(seconds: 60),
  Future<void> Function()? between,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    expect(
      DateTime.now().isBefore(deadline),
      isTrue,
      reason: '$what timed out',
    );
    await tester.pump(const Duration(milliseconds: 400));
    if (between != null) await between();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const enabled = bool.fromEnvironment('SCREENSHOTS');

  testWidgets(
    'screenshots: sheet pending, sheet, card, settings',
    skip: !enabled,
    (tester) async {
      final frames = FakeFrameSource();
      final translator = FakeSentenceTranslator(
        translations: const {_bubbleText: _translation},
      )..manual = true;
      final inference = LazyInference.production();
      final deps = AppDependencies(
        frameSource: frames,
        cameraPreview: (_) => const ColoredBox(color: Color(0xFF202020)),
        photoPicker: FakePhotoPicker(),
        detector: inference.detector,
        ocr: inference.ocr,
        dictionary: LazyDictionary(asset: BundledDictionaryAsset()),
        anki: FakeAnkiExporter(),
        settingsRepository: FakeSettingsRepository(),
        captureLog: FakeOcrCaptureLog(),
        translator: translator,
      );
      final page = await renderPage();

      await tester.pumpWidget(YomitanukiApp(dependencies: deps));
      await tester.pumpAndSettle();
      frames.emit(page);

      final overlay = find.byKey(const Key('reader.overlay'));
      final mapping = FrameMapping.cover(
        frame: _frameSize,
        preview: tester.getSize(overlay),
      );
      final target =
          tester.getTopLeft(overlay) + mapping.toPreviewPoint(_bubbleCentre);
      await _waitFor(
        tester,
        find.byKey(const Key('ocr.sheet')),
        'first detection',
        timeout: const Duration(seconds: 120),
        between: () => tester.tapAt(target),
      );
      await _waitFor(tester, find.byKey(const Key('ocr.char.0')), 'OCR');
      await _waitFor(tester, find.byKey(const Key('ocr.gloss.0')), 'gloss');
      await _waitFor(
        tester,
        find.byKey(const Key('ocr.translation.pending')),
        'pending translation',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('1-sheet-pending');

      translator.pending.single.complete();
      await _waitFor(
        tester,
        find.byKey(const Key('ocr.translation')),
        'translation',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('2-sheet');

      await tester.tap(find.byKey(const Key('ocr.char.0')));
      await _waitFor(tester, find.text('まおう'), 'lookup');
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('3-card');

      await tester.tap(find.byKey(const Key('ocr.close')));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('4-reader');

      await tester.tap(find.byKey(const Key('reader.settings')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('5-settings');
    },
  );
}
