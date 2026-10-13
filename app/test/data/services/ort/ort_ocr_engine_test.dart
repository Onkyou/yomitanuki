import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/ort/model_assets.dart';
import 'package:yomitanuki/data/services/ort/ort_ocr_engine.dart';

import '../../../support/goldens.dart';
import '../../../support/ort_test_env.dart';
import '../../../support/timing.dart';

void main() {
  group('WP0b OCR goldens, CPU execution provider', () {
    final models = modelDirectory();
    final built = manifestSha256s(models);
    final goldens = loadOcrGoldens(goldensDirectory());
    final timing = Timing();
    late OrtOcrEngine engine;

    setUpAll(() async {
      engine = await OrtOcrEngine.create(
        assets: ModelAssets.inDirectory(models),
        ortLibraryPath: ortLibraryPath(),
      );
    });
    tearDownAll(() async {
      await engine.dispose();
      timing.report('ocr');
    });

    test('the .bgra fixtures are row-padded, so they take the repack path', () {
      final padded = goldens.where((g) => g.name.endsWith('.bgra'));
      expect(padded.length, 2);
      expect(padded.every((g) => g.rowPadded), isTrue);
    });

    for (final golden in goldens) {
      test('${golden.name} reads the recorded ids and text', () async {
        expectGoldenModels(golden.modelsSha256, built);

        final got = await timing.measure(
          'cpu ${golden.name}',
          () => engine.recogniseDetailed(golden.image),
        );

        expect(got.ids, golden.ids);
        expect(got.text, golden.text);
        expect(got.steps, golden.ids.length - 1);
      });
    }

    test('recognise answers the port with text and elapsed time', () async {
      final golden = goldens.firstWhere((g) => g.name == 'v_single.png');

      final result = await engine.recognise(golden.image);

      expect(result.text, golden.text);
      expect(result.elapsed, greaterThan(Duration.zero));
    });
  });
}
