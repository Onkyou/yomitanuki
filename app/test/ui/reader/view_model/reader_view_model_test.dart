import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';
import 'package:yomitanuki/domain/models/anki_settings.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_state.dart';
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

/// Everything a test needs, with a hand-driven clock starting at [t0].
class Harness {
  Harness({List<TextBlock> blocks = const [block], String ocrText = '食べられなかった'})
    : detector = FakeTextDetector(blocks: blocks),
      ocr = FakeOcrEngine(text: ocrText) {
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
    viewModel.addListener(() => notifications++);
  }

  static final t0 = DateTime.utc(2026, 10, 13, 20);
  DateTime now = t0;

  final frames = FakeFrameSource();
  final photos = FakePhotoPicker();
  final FakeTextDetector detector;
  final FakeOcrEngine ocr;
  final dictionary = FakeDictionary(
    results: [taberareNakattaResult],
    kanjiEntries: {'食': shokuKanji},
  );
  final anki = FakeAnkiExporter();
  final settings = FakeSettingsRepository();
  late final ReaderViewModel viewModel;
  int notifications = 0;

  void advance(Duration d) => now = now.add(d);

  /// Starts the camera and delivers one frame, detected immediately.
  Future<void> startWithFrame({int seed = 1}) async {
    await viewModel.start();
    frames.emit(testImage(100, 100, seed: seed));
    await pumpEventQueue();
  }

  /// Start, frame, detect, tap the block: the OCR sheet is open.
  Future<void> openOcrSheet() async {
    await startWithFrame();
    await viewModel.onTapBlock(block);
  }
}

void main() {
  group('camera lifecycle', () {
    test('start() starts the frame source and reports live', () async {
      final h = Harness();
      expect(h.viewModel.cameraState, isA<CameraIdle>());

      await h.viewModel.start();

      expect(h.frames.startCalls, 1);
      expect(h.viewModel.cameraState, isA<CameraLive>());
    });

    test('a permission error becomes a failed state, not a crash', () async {
      final h = Harness();
      h.frames.startError = const CameraPermissionDeniedError();

      await h.viewModel.start();

      final state = h.viewModel.cameraState;
      expect(state, isA<CameraFailed>());
      expect((state as CameraFailed).message, contains('Camera access'));
      expect(state.permissionDenied, isTrue);
    });

    test('an unavailable camera is a failed state without the Settings '
        'hint', () async {
      final h = Harness();
      h.frames.startError = const CameraUnavailableError('no back camera');

      await h.viewModel.start();

      final state = h.viewModel.cameraState;
      expect(state, isA<CameraFailed>());
      expect((state as CameraFailed).permissionDenied, isFalse);
    });

    test('an error on the frame stream becomes a failed state', () async {
      final h = Harness();
      await h.viewModel.start();

      h.frames.emitError(const CameraPermissionDeniedError());
      await pumpEventQueue();

      final state = h.viewModel.cameraState;
      expect(state, isA<CameraFailed>());
      expect((state as CameraFailed).permissionDenied, isTrue);
    });

    test(
      'stop() then start() restarts the source (AnkiMobile round trip)',
      () async {
        final h = Harness();
        await h.viewModel.start();
        await h.viewModel.stop();
        expect(h.viewModel.cameraState, isA<CameraIdle>());

        await h.viewModel.start();

        expect(h.frames.startCalls, 2);
        expect(h.frames.stopCalls, 1);
        expect(h.viewModel.cameraState, isA<CameraLive>());
      },
    );
  });

  group('detection sampling (D0.13)', () {
    test(
      'the first frame is detected at once and its blocks exposed',
      () async {
        final h = Harness();

        await h.startWithFrame();

        expect(h.detector.calls, hasLength(1));
        expect(h.viewModel.blocks, [block]);
        expect(h.viewModel.frameSize, const Size(100, 100));
        expect(h.viewModel.scanning, isFalse);
      },
    );

    test('frames inside the interval are dropped, the next one after it is detected', () async {
      final h = Harness();
      await h.startWithFrame();

      h.advance(const Duration(milliseconds: 300));
      h.frames.emit(testImage(100, 100, seed: 2));
      h.advance(const Duration(milliseconds: 699));
      h.frames.emit(testImage(100, 100, seed: 3));
      await pumpEventQueue();
      expect(h.detector.calls, hasLength(1));

      h.advance(const Duration(milliseconds: 1));
      h.frames.emit(testImage(100, 100, seed: 4));
      await pumpEventQueue();

      expect(h.detector.calls, hasLength(2));
      expect(h.detector.calls.last.bytes[2], 4);
    });

    test(
      'frames arriving while a detection is in flight are dropped',
      () async {
        final h = Harness();
        h.detector.hold();
        await h.viewModel.start();
        h.frames.emit(testImage(100, 100, seed: 1));
        expect(h.viewModel.scanning, isTrue);

        h.advance(const Duration(seconds: 2));
        h.frames.emit(testImage(100, 100, seed: 2));
        await pumpEventQueue();
        expect(h.detector.calls, hasLength(1));

        h.detector.release();
        await pumpEventQueue();

        expect(h.viewModel.scanning, isFalse);
        expect(h.viewModel.blocks, [block]);
      },
    );

    test(
      'a detector error is a user-visible message, blocks are cleared',
      () async {
        final h = Harness();
        await h.startWithFrame();
        h.detector.error = NotWiredError('TextDetector');

        h.advance(const Duration(seconds: 1));
        h.frames.emit(testImage(100, 100, seed: 2));
        await pumpEventQueue();

        expect(h.viewModel.blocks, isEmpty);
        expect(h.viewModel.notice, contains('TextDetector'));
        expect(h.viewModel.scanning, isFalse);
      },
    );

    test('sampling pauses while the OCR sheet is open and the very next frame '
        'after dismiss is detected, interval or not', () async {
      final h = Harness();
      await h.openOcrSheet();

      h.advance(const Duration(milliseconds: 300));
      h.frames.emit(testImage(100, 100, seed: 2));
      await pumpEventQueue();
      expect(h.detector.calls, hasLength(1));

      // 0.6 s after the last sample, inside the 1 s interval: without the
      // reset on dismiss this frame would be dropped and the boxes stale.
      h.viewModel.dismissOcr();
      h.advance(const Duration(milliseconds: 300));
      h.frames.emit(testImage(100, 100, seed: 3));
      await pumpEventQueue();

      expect(h.detector.calls, hasLength(2));
      expect(h.viewModel.ocrState, isA<OcrIdle>());
    });
  });

  group('OCR on tap', () {
    test('crops the tapped block, with an 8 % margin, from the frame the blocks came from', () async {
      final h = Harness();
      await h.startWithFrame(seed: 1);
      // A newer frame is being detected; the blocks on screen still belong to
      // frame 1, so the crop must come from frame 1.
      h.detector.hold();
      h.advance(const Duration(seconds: 1));
      h.frames.emit(testImage(100, 100, seed: 2));

      await h.viewModel.onTapBlock(block);

      final crop = h.ocr.crops.single;
      expect(crop.bytes[2], 1, reason: 'crop must come from frame 1');
      // 20 px box, 8 % margin = 1.6 px each side: left 8.4 -> 8, width 23.2 -> 23.
      expect(crop.width, 23);
      expect(crop.height, 23);
      expect(crop.bytes[0], 8, reason: 'first pixel x');
      expect(crop.bytes[1], 8, reason: 'first pixel y');
      h.detector.release();
    });

    test('goes running then shows the text, notifying on both', () async {
      final h = Harness();
      await h.startWithFrame();
      h.ocr.hold();

      final done = h.viewModel.onTapBlock(block);
      expect(h.viewModel.ocrState, isA<OcrRunning>());
      final notifiedWhileRunning = h.notifications;

      h.ocr.release();
      await done;

      final state = h.viewModel.ocrState;
      expect(state, isA<OcrText>());
      expect((state as OcrText).text, '食べられなかった');
      expect(state.block, block);
      expect(h.viewModel.lookupState, isA<LookupIdle>());
      expect(
        h.notifications,
        greaterThan(notifiedWhileRunning),
        reason: 'the view must be told the text arrived',
      );
    });

    test(
      'dismissing the sheet during OCR keeps it closed (Prove-It)',
      () async {
        final h = Harness();
        await h.startWithFrame();
        h.ocr.hold();
        final reading = h.viewModel.onTapBlock(block);

        h.viewModel.dismissOcr();
        h.ocr.release();
        await reading;

        expect(h.viewModel.ocrState, isA<OcrIdle>());
      },
    );

    test('an OCR error is shown in the sheet', () async {
      final h = Harness();
      await h.startWithFrame();
      h.ocr.error = NotWiredError('OcrEngine');

      await h.viewModel.onTapBlock(block);

      final state = h.viewModel.ocrState;
      expect(state, isA<OcrFailed>());
      expect((state as OcrFailed).message, contains('OcrEngine'));
    });

    test('a tap before any frame is ignored', () async {
      final h = Harness();
      await h.viewModel.start();

      await h.viewModel.onTapBlock(block);

      expect(h.ocr.crops, isEmpty);
      expect(h.viewModel.ocrState, isA<OcrIdle>());
    });
  });

  group('lookup on character tap', () {
    test(
      'looks up from the tapped character and attaches the kanji breakdown',
      () async {
        final h = Harness();
        await h.openOcrSheet();

        await h.viewModel.onTapCharacter(0);

        expect(h.dictionary.lookups, [('食べられなかった', 0)]);
        final state = h.viewModel.lookupState;
        expect(state, isA<LookupResults>());
        final results = state as LookupResults;
        expect(results.index, 0);
        expect(results.results, [taberareNakattaResult]);
        expect(results.kanji.keys, ['食']);
        expect(h.dictionary.kanjiLookups, ['食']);
      },
    );

    test(
      'a later tap wins over an earlier, slower lookup (Prove-It)',
      () async {
        final h = Harness();
        h.dictionary.manual = true;
        h.dictionary.onLookup = (text, index) =>
            index == 0 ? [taberareNakattaResult] : [];
        await h.openOcrSheet();

        final first = h.viewModel.onTapCharacter(0);
        final second = h.viewModel.onTapCharacter(3);
        await pumpEventQueue();
        h.dictionary.pending[1].complete(); // the second answers first
        await second;
        h.dictionary.pending[0].complete(); // the first answers late
        await first;

        final state = h.viewModel.lookupState;
        expect(state, isA<LookupResults>());
        expect((state as LookupResults).index, 3);
        expect(state.results, isEmpty);
      },
    );

    test('no match is an empty result list, not an error', () async {
      final h = Harness();
      h.dictionary.results = [];
      await h.openOcrSheet();

      await h.viewModel.onTapCharacter(3);

      final state = h.viewModel.lookupState;
      expect(state, isA<LookupResults>());
      expect((state as LookupResults).results, isEmpty);
    });

    test('a dictionary error is a failed lookup', () async {
      final h = Harness();
      h.dictionary.error = NotWiredError('Dictionary');
      await h.openOcrSheet();

      await h.viewModel.onTapCharacter(0);

      final state = h.viewModel.lookupState;
      expect(state, isA<LookupFailed>());
      expect((state as LookupFailed).message, contains('Dictionary'));
    });

    test('tapping a character without OCR text is ignored', () async {
      final h = Harness();

      await h.viewModel.onTapCharacter(0);

      expect(h.dictionary.lookups, isEmpty);
      expect(h.viewModel.lookupState, isA<LookupIdle>());
    });
  });

  group('add to Anki', () {
    test('builds the note with AnkiNoteBuilder from the entry, the OCR line '
        'and the stored settings', () async {
      final h = Harness();
      h.settings.stored = AnkiSettings.defaults.copyWith(
        deck: 'Deck::X',
        noteType: 'Type Y',
      );
      await h.openOcrSheet();
      await h.viewModel.onTapCharacter(0);

      await h.viewModel.addToAnki(taberareNakattaResult);

      final note = h.anki.notes.single;
      expect(note.deck, 'Deck::X');
      expect(note.noteType, 'Type Y');
      expect(note.fields, {
        'Word': '食べる',
        'Reading': 'たべる',
        'Meaning': '1. to eat<br>2. to live on (e.g. a salary)',
        'Example': '食べられなかった',
        'ExampleEN': '',
        'Note': '',
      });
      expect(h.viewModel.ankiMessage, isA<AnkiHandedOver>());
    });

    test('nothing stored means the Frieren deck and note type', () async {
      final h = Harness();
      await h.openOcrSheet();

      await h.viewModel.addToAnki(taberareNakattaResult);

      final note = h.anki.notes.single;
      expect(note.deck, 'Japanese::Frieren Vol. 1');
      expect(note.noteType, 'Frieren Vocab (JP→EN)');
    });

    test('settings are loaded for every note, so an edit mid-session '
        'applies to the next add', () async {
      final h = Harness();
      await h.openOcrSheet();
      await h.viewModel.addToAnki(taberareNakattaResult);

      h.settings.stored = AnkiSettings.defaults.copyWith(deck: 'Later');
      await h.viewModel.addToAnki(taberareNakattaResult);

      expect(h.anki.notes.map((n) => n.deck), [
        'Japanese::Frieren Vol. 1',
        'Later',
      ]);
    });

    test('settings the builder refuses become a message pointing at '
        'Settings, and nothing is sent', () async {
      final h = Harness();
      h.settings.stored = AnkiSettings.defaults.copyWith(deck: '  ');
      await h.openOcrSheet();

      await h.viewModel.addToAnki(taberareNakattaResult);

      expect(h.anki.notes, isEmpty);
      final message = h.viewModel.ankiMessage;
      expect(message, isA<AnkiFailed>());
      expect(
        (message as AnkiFailed).message,
        contains('Deck must not be empty'),
      );
      expect(message.message, contains('Settings'));
    });

    test('a failing settings load is a failed message', () async {
      final h = Harness();
      h.settings.failure = Exception('prefs unavailable');
      await h.openOcrSheet();

      await h.viewModel.addToAnki(taberareNakattaResult);

      expect(h.anki.notes, isEmpty);
      expect(h.viewModel.ankiMessage, isA<AnkiFailed>());
    });

    test('reports when AnkiMobile is not installed', () async {
      final h = Harness();
      h.anki.outcome = AnkiExportOutcome.ankiNotInstalled;
      await h.openOcrSheet();

      await h.viewModel.addToAnki(taberareNakattaResult);

      expect(h.viewModel.ankiMessage, isA<AnkiNotInstalled>());
    });

    test('an exporter error is a failed message, consumed once', () async {
      final h = Harness();
      h.anki.error = NotWiredError('AnkiExporter');
      await h.openOcrSheet();

      await h.viewModel.addToAnki(taberareNakattaResult);

      final message = h.viewModel.ankiMessage;
      expect(message, isA<AnkiFailed>());
      expect((message as AnkiFailed).message, contains('AnkiExporter'));

      h.viewModel.consumeAnkiMessage();
      expect(h.viewModel.ankiMessage, isNull);
    });
  });

  group('photo fallback', () {
    test('a picked photo stops the camera and is detected at once', () async {
      final h = Harness();
      await h.startWithFrame(seed: 1);
      h.photos.photo = testImage(50, 80, seed: 7);

      await h.viewModel.pickPhoto();

      expect(h.viewModel.source, ReaderSource.photo);
      expect(h.frames.stopCalls, 1);
      expect(h.detector.calls, hasLength(2));
      expect(h.detector.calls.last.bytes[2], 7);
      expect(h.viewModel.frameSize, const Size(50, 80));
      expect(h.viewModel.frame, same(h.photos.photo));
    });

    test('camera frames are ignored while a photo is shown', () async {
      final h = Harness();
      await h.startWithFrame();
      h.photos.photo = testImage(50, 80, seed: 7);
      await h.viewModel.pickPhoto();

      h.advance(const Duration(seconds: 5));
      h.frames.emit(testImage(100, 100, seed: 9));
      await pumpEventQueue();

      expect(h.detector.calls, hasLength(2));
      expect(h.viewModel.frame!.bytes[2], 7);
    });

    test('cancelling the picker changes nothing', () async {
      final h = Harness();
      await h.startWithFrame();

      await h.viewModel.pickPhoto();

      expect(h.viewModel.source, ReaderSource.camera);
      expect(h.frames.stopCalls, 0);
      expect(h.detector.calls, hasLength(1));
    });

    test('backToCamera() restarts the stream', () async {
      final h = Harness();
      await h.startWithFrame();
      h.photos.photo = testImage(50, 80, seed: 7);
      await h.viewModel.pickPhoto();

      await h.viewModel.backToCamera();

      expect(h.viewModel.source, ReaderSource.camera);
      expect(h.frames.startCalls, 2);
      expect(h.viewModel.blocks, isEmpty);
      expect(h.viewModel.cameraState, isA<CameraLive>());
    });

    test('a picker error is a user-visible message', () async {
      final h = Harness();
      h.photos.error = StateError('gallery unavailable');
      await h.startWithFrame();

      await h.viewModel.pickPhoto();

      expect(h.viewModel.source, ReaderSource.camera);
      expect(h.viewModel.notice, 'Something went wrong. Please try again.');
    });
  });

  group('results land only in the state that asked for them (D4.16)', () {
    test(
      'backToCamera during a photo detection drops the photo result',
      () async {
        final h = Harness();
        await h.startWithFrame();
        h.photos.photo = testImage(50, 80, seed: 7);
        h.detector.hold();
        final picking = h.viewModel.pickPhoto();
        await pumpEventQueue();
        expect(h.viewModel.source, ReaderSource.photo);

        final returning = h.viewModel.backToCamera();
        h.detector.release();
        await picking;
        await returning;

        expect(h.viewModel.source, ReaderSource.camera);
        expect(h.viewModel.frame, isNull);
        expect(h.viewModel.blocks, isEmpty);
      },
    );

    test(
      'pickPhoto while a camera detection is in flight keeps the photo',
      () async {
        final h = Harness();
        await h.startWithFrame(seed: 1);
        h.detector.hold();
        h.advance(const Duration(seconds: 1));
        h.frames.emit(testImage(100, 100, seed: 2));
        expect(h.viewModel.scanning, isTrue);
        h.photos.photo = testImage(50, 80, seed: 7);

        final picking = h.viewModel.pickPhoto();
        await pumpEventQueue();
        h.detector.release();
        await picking;

        expect(h.viewModel.frame!.bytes[2], 7);
        expect(h.viewModel.scanning, isFalse);
      },
    );

    test('the photo shows at once, without the last camera frame under '
        'stale boxes', () async {
      final h = Harness();
      await h.startWithFrame(seed: 1);
      h.photos.photo = testImage(50, 80, seed: 7);
      h.detector.hold();

      final picking = h.viewModel.pickPhoto();
      await pumpEventQueue();

      expect(h.viewModel.frame!.bytes[2], 7);
      expect(h.viewModel.blocks, isEmpty);
      expect(h.viewModel.scanning, isTrue);
      h.detector.release();
      await picking;
    });

    test('stop() drops a camera detection that was in flight', () async {
      final h = Harness();
      await h.viewModel.start();
      h.detector.hold();
      h.frames.emit(testImage(100, 100, seed: 1));

      await h.viewModel.stop();
      h.detector.release();
      await pumpEventQueue();

      expect(h.viewModel.frame, isNull);
    });
  });

  group('no bubbles hint', () {
    test('shows after three consecutive empty detections and clears on '
        'the next hit', () async {
      final h = Harness(blocks: const []);
      await h.startWithFrame();
      for (var i = 0; i < 2; i++) {
        h.advance(const Duration(seconds: 1));
        h.frames.emit(testImage(100, 100));
        await pumpEventQueue();
      }
      expect(h.detector.calls, hasLength(3));
      expect(h.viewModel.noBlocksHint, isTrue);

      h.detector.blocks = const [block];
      h.advance(const Duration(seconds: 1));
      h.frames.emit(testImage(100, 100));
      await pumpEventQueue();

      expect(h.viewModel.noBlocksHint, isFalse);
    });

    test('two empty detections are not enough', () async {
      final h = Harness(blocks: const []);
      await h.startWithFrame();
      h.advance(const Duration(seconds: 1));
      h.frames.emit(testImage(100, 100));
      await pumpEventQueue();

      expect(h.viewModel.noBlocksHint, isFalse);
    });
  });

  test('blocks and lookup results are unmodifiable', () async {
    final h = Harness();
    await h.openOcrSheet();
    await h.viewModel.onTapCharacter(0);

    expect(() => h.viewModel.blocks.clear(), throwsUnsupportedError);
    final results = (h.viewModel.lookupState as LookupResults).results;
    expect(results.clear, throwsUnsupportedError);
  });

  test('dispose() stops listening to frames', () async {
    final h = Harness();
    await h.startWithFrame();

    h.viewModel.dispose();
    h.advance(const Duration(seconds: 2));
    h.frames.emit(testImage(100, 100, seed: 2));
    await pumpEventQueue();

    expect(h.detector.calls, hasLength(1));
  });
}
