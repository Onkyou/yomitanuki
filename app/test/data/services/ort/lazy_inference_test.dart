import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';
import 'package:yomitanuki/data/services/ort/inference_error.dart';
import 'package:yomitanuki/data/services/ort/lazy_inference.dart';
import 'package:yomitanuki/data/services/ort/model_assets.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

import '../../../fakes/fake_ocr_engine.dart';
import '../../../fakes/fake_text_detector.dart';

/// Counts and scripts the three creation steps.
class _Steps {
  int prepares = 0;
  int detectors = 0;
  int ocrs = 0;

  /// Thrown by the next prepare / create when set, then cleared.
  Exception? prepareFailure;
  Exception? detectorFailure;

  final detector = FakeTextDetector();
  final ocr = FakeOcrEngine(text: 'ok');

  late final LazyInference lazy = LazyInference(
    prepare: () async {
      prepares++;
      final f = prepareFailure;
      if (f != null) {
        prepareFailure = null;
        throw f;
      }
      return ModelAssets.inDirectory(Directory('/nowhere'));
    },
    detector: (_) async {
      detectors++;
      final f = detectorFailure;
      if (f != null) {
        detectorFailure = null;
        throw f;
      }
      return detector;
    },
    ocr: (_) async {
      ocrs++;
      return ocr;
    },
  );
}

final _image = BgraImage(width: 2, height: 2, bytes: Uint8List(16));

void main() {
  test(
    'concurrent first calls prepare once and create each adapter once',
    () async {
      final s = _Steps();

      await Future.wait([
        s.lazy.detector.detect(_image),
        s.lazy.detector.detect(_image),
        s.lazy.ocr.recognise(_image),
        s.lazy.ocr.recognise(_image),
      ]);

      expect(s.prepares, 1);
      expect(s.detectors, 1);
      expect(s.ocrs, 1);
      expect(s.detector.calls.length, 2);
      expect(s.ocr.crops.length, 2);
    },
  );

  test('nothing is created until the first call', () {
    final s = _Steps();

    expect(s.prepares, 0);
    expect(s.detectors, 0);
    expect(s.ocrs, 0);
  });

  test(
    'a failed preparation is ModelsUnavailableError and is retried',
    () async {
      final s = _Steps()..prepareFailure = ModelAssetsException('no models');

      await expectLater(
        s.lazy.detector.detect(_image),
        throwsA(
          isA<ModelsUnavailableError>().having(
            (e) => e.reason,
            'reason',
            contains('no models'),
          ),
        ),
      );
      await s.lazy.detector.detect(_image);

      expect(s.prepares, 2);
      expect(s.detectors, 1);
    },
  );

  test('a failed adapter creation is InferenceFailedError, retried', () async {
    final s = _Steps()
      ..detectorFailure = OrtException(OrtErrorCode.fail, 'cannot load');

    await expectLater(
      s.lazy.detector.detect(_image),
      throwsA(isA<InferenceFailedError>()),
    );
    await s.lazy.detector.detect(_image);

    expect(s.prepares, 1);
    expect(s.detectors, 2);
  });

  test(
    'the adapters\' errors reach the reader as InferenceFailedError',
    () async {
      final s = _Steps();
      s.detector.error = InferenceError('frame geometry');
      s.ocr.error = OrtException(OrtErrorCode.runtimeException, 'boom');

      await expectLater(
        s.lazy.detector.detect(_image),
        throwsA(
          isA<InferenceFailedError>().having(
            (e) => e.reason,
            'reason',
            contains('frame geometry'),
          ),
        ),
      );
      await expectLater(
        s.lazy.ocr.recognise(_image),
        throwsA(isA<InferenceFailedError>()),
      );
    },
  );

  test('other errors pass through unchanged', () async {
    final s = _Steps();
    s.detector.error = StateError('used after dispose');

    await expectLater(s.lazy.detector.detect(_image), throwsStateError);
  });

  test('dispose disposes what was created, and only that', () async {
    final s = _Steps();
    await s.lazy.detector.detect(_image);

    await s.lazy.dispose();

    expect(s.detector.disposed, isTrue);
    expect(s.ocr.disposed, isFalse);
    expect(s.ocrs, 0);
  });

  test(
    'a port\'s dispose covers its own adapter; the next call recreates',
    () async {
      final s = _Steps();
      await s.lazy.ocr.recognise(_image);

      await s.lazy.ocr.dispose();
      await s.lazy.ocr.recognise(_image);

      expect(s.ocr.disposed, isTrue);
      expect(s.ocrs, 2);
      expect(s.prepares, 1);
    },
  );

  test('dispose before anything was created is a no-op', () async {
    final s = _Steps();

    await s.lazy.dispose();

    expect(s.prepares, 0);
  });

  test('production wiring constructs without touching the platform', () {
    expect(LazyInference.production().detector, isNotNull);
  });
}
