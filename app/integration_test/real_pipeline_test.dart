// The real pipeline end to end on the iOS Simulator: the ONNX detector, the
// ONNX OCR engine and the bundled dictionary, fed one frame that this test
// renders itself (a white page, one outlined speech bubble, vertical text).
// Only the camera, the photo picker, Anki and settings are faked. The first
// detection also pays the model-asset copy and the session loads, so waits
// are generous. Run with `make gate-integration`.
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
import '../test/fakes/fake_photo_picker.dart';
import '../test/fakes/fake_settings_repository.dart';

const _frameSize = Size(1080, 1920);
const _bubbleCentre = Offset(540, 760);
const _bubbleText = '魔王を倒した勇者';

/// A 1080x1920 page: panel border, one elliptical bubble with [_bubbleText]
/// written top to bottom, rendered through dart:ui and decoded like a photo.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real detector, OCR and dictionary read a rendered bubble', (
    tester,
  ) async {
    final frames = FakeFrameSource();
    final anki = FakeAnkiExporter();
    final inference = LazyInference.production();
    final deps = AppDependencies(
      frameSource: frames,
      cameraPreview: (_) => const ColoredBox(color: Colors.black),
      photoPicker: FakePhotoPicker(),
      detector: inference.detector,
      ocr: inference.ocr,
      dictionary: LazyDictionary(asset: BundledDictionaryAsset()),
      anki: anki,
      settingsRepository: FakeSettingsRepository(),
    );
    final page = await renderPage();

    await tester.pumpWidget(YomitanukiApp(dependencies: deps));
    await tester.pumpAndSettle();
    frames.emit(page);

    // The first detection copies the models and loads the sessions; poll by
    // tapping the bubble until the OCR sheet opens (a tap outside any box
    // does nothing, D0.11).
    final overlay = find.byKey(const Key('reader.overlay'));
    final mapping = FrameMapping.cover(
      frame: _frameSize,
      preview: tester.getSize(overlay),
    );
    final target =
        tester.getTopLeft(overlay) + mapping.toPreviewPoint(_bubbleCentre);
    final sheet = find.byKey(const Key('ocr.sheet'));
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (sheet.evaluate().isEmpty) {
      expect(
        DateTime.now().isBefore(deadline),
        isTrue,
        reason: 'no tappable block appeared within 120 s',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 500));
    }

    // OCR: the sheet shows the recognised characters, one cell each.
    final ocrDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (find.byKey(const Key('ocr.char.0')).evaluate().isEmpty) {
      expect(
        DateTime.now().isBefore(ocrDeadline),
        isTrue,
        reason: 'OCR did not finish within 60 s',
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('魔'), findsWidgets);
    expect(find.text('王'), findsWidgets);

    // Dictionary: tapping 魔 looks up 魔王 (まおう) in the bundled JMdict.
    await tester.tap(find.byKey(const Key('ocr.char.0')));
    final lookupDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.text('まおう').evaluate().isEmpty) {
      expect(
        DateTime.now().isBefore(lookupDeadline),
        isTrue,
        reason: 'no dictionary entry for 魔王 within 30 s',
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.textContaining('demon'), findsWidgets);

    await tester.tap(find.byKey(const Key('anki.add.0')));
    await tester.pumpAndSettle();
    expect(anki.notes.single.fields['Word'], '魔王');

    await inference.dispose();
  });
}
