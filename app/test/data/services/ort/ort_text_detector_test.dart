import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/ort/model_assets.dart';
import 'package:yomitanuki/data/services/ort/ort_text_detector.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/models/text_block.dart';

import '../../../support/goldens.dart';
import '../../../support/ort_test_env.dart';
import '../../../support/timing.dart';

void main() {
  group('toTextBlocks', () {
    test('maps every [x0,y0,x1,y1,score] row in order, clamped', () {
      final blocks = OrtTextDetector.toTextBlocks(
        Float32List.fromList([
          10, 20, 30, 40, 0.75, //
          -5, -1, 105, 203, 0.5, //
        ]),
        width: 100,
        height: 200,
      );

      expect(blocks, [
        // Scores exactly representable in float32.
        const TextBlock(box: Rect.fromLTRB(10, 20, 30, 40), confidence: 0.75),
        const TextBlock(box: Rect.fromLTRB(0, 0, 100, 200), confidence: 0.5),
      ]);
    });

    test('N = 0 is an empty list', () {
      expect(
        OrtTextDetector.toTextBlocks(Float32List(0), width: 10, height: 10),
        isEmpty,
      );
    });

    test('a row count that is not a multiple of five is refused', () {
      expect(
        () =>
            OrtTextDetector.toTextBlocks(Float32List(7), width: 10, height: 10),
        throwsArgumentError,
      );
    });
  });

  group('create', () {
    final assets = ModelAssets.inDirectory(modelDirectory());

    test('refuses a confidence threshold outside [0, 1]', () {
      expect(
        () => OrtTextDetector.create(
          assets: assets,
          confThreshold: 1.5,
          coreMl: false,
          ortLibraryPath: ortLibraryPath(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('WP0b detector goldens', () {
    final models = modelDirectory();
    final assets = ModelAssets.inDirectory(models);
    final built = manifestSha256s(models);
    final goldens = loadDetectorGoldens(goldensDirectory());
    final timing = Timing();

    tearDownAll(() => timing.report('detector'));

    group('CPU execution provider (exact)', () {
      late OrtTextDetector detector;

      setUpAll(() async {
        detector = await OrtTextDetector.create(
          assets: assets,
          coreMl: false,
          ortLibraryPath: ortLibraryPath(),
        );
      });
      tearDownAll(() => detector.dispose());

      for (final golden in goldens) {
        test('${golden.name} gives the recorded blocks', () async {
          expectGoldenModels(golden.modelsSha256, built);
          expect(detector.confThreshold, golden.confThreshold);

          final got = await timing.measure(
            'cpu ${golden.name}',
            () => detector.detect(golden.image),
          );

          expect(blockMismatches(got, golden), isEmpty);
          expect(got.map((b) => b.confidence), _descending);
        });
      }
    });

    group('CoreML execution provider (D0.10 + D0b.6)', () {
      late Directory cache;
      late OrtTextDetector detector;

      setUpAll(() async {
        cache = tempDirectory('coreml_cache_');
        detector = await OrtTextDetector.create(
          assets: assets,
          coreMlCacheDirectory: cache.path,
          ortLibraryPath: ortLibraryPath(),
        );
      });
      tearDownAll(() async {
        await detector.dispose();
        cache.deleteSync(recursive: true);
      });

      for (final golden in goldens) {
        // Threshold-edge boxes may appear or vanish under ANE fp16 (D0b.6),
        // so: the count within one, every other golden block matched.
        test('${golden.name} gives the recorded blocks, within one', () async {
          expectGoldenModels(golden.modelsSha256, built);

          final got = await timing.measure(
            'coreml ${golden.name}',
            () => detector.detect(golden.image),
          );

          final mismatches = blockMismatches(got, golden);
          final unmatchedGolden = mismatches
              .where((m) => m.startsWith('no output block'))
              .length;
          final unexpected = mismatches
              .where((m) => m.startsWith('unexpected'))
              .length;
          expect(
            unmatchedGolden,
            lessThanOrEqualTo(1),
            reason: mismatches.join('\n'),
          );
          expect(
            unexpected,
            lessThanOrEqualTo(1),
            reason: mismatches.join('\n'),
          );
          expect(
            (got.length - golden.blocks.length).abs(),
            lessThanOrEqualTo(1),
          );
        });
      }

      test(
        'a blank 1080x1920 frame gives no blocks and does not throw',
        () async {
          const width = 1080;
          const height = 1920;
          final blank = BgraImage(
            width: width,
            height: height,
            bytes: Uint8List(width * height * 4)
              ..fillRange(0, width * height * 4, 255),
          );

          expect(await detector.detect(blank), isEmpty);
        },
      );
    });
  });
}

final Matcher _descending = predicate<Iterable<double>>((scores) {
  final list = scores.toList();
  for (var i = 1; i < list.length; i++) {
    if (list[i] > list[i - 1]) return false;
  }
  return true;
}, 'sorted by confidence, highest first');
