import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';
import 'package:yomitanuki/data/services/ort/inference_error.dart';
import 'package:yomitanuki/data/services/ort/model_assets.dart';
import 'package:yomitanuki/data/services/ort/ort_inference_worker.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

import '../../../support/goldens.dart';
import '../../../support/ort_test_env.dart';

void main() {
  final assets = ModelAssets.inDirectory(modelDirectory());
  final page = loadDetectorGoldens(goldensDirectory()).first;

  OrtWorkerConfig detectorOnly({ModelAssets? from}) => OrtWorkerConfig(
    assets: from ?? assets,
    graphs: const {WorkerGraphs.detector},
    ortLibraryPath: ortLibraryPath(),
  );

  BgraImage white(int width, int height) => BgraImage(
    width: width,
    height: height,
    bytes: Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255),
  );

  test('two concurrent requests each get their own answer', () async {
    final worker = await OrtInferenceWorker.spawn(detectorOnly());
    try {
      final blank = worker.detect(white(640, 480), confThreshold: 0.2);
      final golden = worker.detect(
        page.image,
        confThreshold: page.confThreshold,
      );

      final (blankBlocks, goldenBlocks) = await (blank, golden).wait;

      expect(blankBlocks, isEmpty);
      expect(goldenBlocks.length ~/ 5, page.blocks.length);
    } finally {
      await worker.dispose();
    }
  });

  test('dispose while a request is in flight fails it, typed', () async {
    final worker = await OrtInferenceWorker.spawn(detectorOnly());
    final inFlight = worker.detect(page.image, confThreshold: 0.2);
    // Attached before the dispose, which fails the future synchronously.
    final failsTyped = expectLater(
      inFlight,
      throwsA(
        isA<InferenceError>().having(
          (e) => e.message,
          'message',
          contains('disposed'),
        ),
      ),
    );

    await worker.dispose();

    await failsTyped;
  });

  test('a request after a failed one is served', () async {
    final worker = await OrtInferenceWorker.spawn(detectorOnly());
    try {
      final short = BgraImage(width: 100, height: 100, bytes: Uint8List(10));
      await expectLater(
        worker.detect(short, confThreshold: 0.2),
        throwsA(
          isA<InferenceError>().having(
            (e) => e.message,
            'message',
            contains('10 bytes'),
          ),
        ),
      );

      expect(await worker.detect(white(64, 64), confThreshold: 0.2), isEmpty);
    } finally {
      await worker.dispose();
    }
  });

  test('a row-padded frame gives the same blocks as the tight one', () async {
    final tight = page.image;
    final bytesPerRow = tight.width * 4 + 12;
    final padded = Uint8List(tight.height * bytesPerRow)
      ..fillRange(0, tight.height * bytesPerRow, 0x5a);
    for (var y = 0; y < tight.height; y++) {
      padded.setRange(
        y * bytesPerRow,
        y * bytesPerRow + tight.width * 4,
        tight.bytes,
        y * tight.width * 4,
      );
    }
    final worker = await OrtInferenceWorker.spawn(detectorOnly());
    try {
      final fromTight = await worker.detect(tight, confThreshold: 0.2);
      final fromPadded = await worker.detect(
        BgraImage(
          width: tight.width,
          height: tight.height,
          bytes: padded,
          bytesPerRow: bytesPerRow,
        ),
        confThreshold: 0.2,
      );

      expect(fromPadded, fromTight);
      expect(fromTight, isNotEmpty);
    } finally {
      await worker.dispose();
    }
  });

  test('a worker without the OCR graphs answers recognise, typed', () async {
    final worker = await OrtInferenceWorker.spawn(detectorOnly());
    try {
      await expectLater(
        worker.recognise(white(64, 64)),
        throwsA(isA<InferenceError>()),
      );
    } finally {
      await worker.dispose();
    }
  });

  test('a missing model file fails spawn with ORT\'s own error', () async {
    final empty = tempDirectory('no_models_');
    try {
      await expectLater(
        OrtInferenceWorker.spawn(
          detectorOnly(from: ModelAssets.inDirectory(empty)),
        ),
        throwsA(
          isA<OrtException>().having(
            (e) => e.code,
            'code',
            OrtErrorCode.noSuchFile,
          ),
        ),
      );
    } finally {
      empty.deleteSync(recursive: true);
    }
  });

  test(
    'requests after dispose are a StateError; dispose twice is fine',
    () async {
      final worker = await OrtInferenceWorker.spawn(detectorOnly());
      await worker.dispose();

      expect(
        () => worker.detect(white(8, 8), confThreshold: 0.2),
        throwsStateError,
      );
      await worker.dispose();
    },
  );
}
