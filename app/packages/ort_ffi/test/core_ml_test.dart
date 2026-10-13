import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';

import 'support/ort_test_env.dart';

void main() {
  group('CoreMlOptions', () {
    test('defaults are WP0 D0.10: NeuralNetwork on CPUAndNeuralEngine', () {
      final options = CoreMlOptions(modelCacheDirectory: '/tmp/cache');

      expect(options.providerOptions, {
        'ModelFormat': 'NeuralNetwork',
        'MLComputeUnits': 'CPUAndNeuralEngine',
        'ModelCacheDirectory': '/tmp/cache',
      });
    });

    test('every format and compute unit spells its ORT key', () {
      expect(
        CoreMlOptions(
          modelFormat: CoreMlModelFormat.mlProgram,
          computeUnits: CoreMlComputeUnits.cpuOnly,
          modelCacheDirectory: 'd',
        ).providerOptions,
        containsPair('ModelFormat', 'MLProgram'),
      );
      expect(
        CoreMlOptions(
          computeUnits: CoreMlComputeUnits.cpuOnly,
          modelCacheDirectory: 'd',
        ).providerOptions,
        containsPair('MLComputeUnits', 'CPUOnly'),
      );
      expect(
        CoreMlOptions(
          computeUnits: CoreMlComputeUnits.cpuAndGpu,
          modelCacheDirectory: 'd',
        ).providerOptions,
        containsPair('MLComputeUnits', 'CPUAndGPU'),
      );
      expect(
        CoreMlOptions(
          computeUnits: CoreMlComputeUnits.all,
          modelCacheDirectory: 'd',
        ).providerOptions,
        containsPair('MLComputeUnits', 'ALL'),
      );
    });
  });

  group('OrtSessionOptions.appendCoreML', () {
    late OrtRuntime runtime;
    late Directory cache;

    setUp(() {
      runtime = OrtRuntime.open(ortLibraryPath());
      cache = Directory.systemTemp.createTempSync('ort_ffi_coreml_');
    });

    tearDown(() {
      runtime.dispose();
      cache.deleteSync(recursive: true);
    });

    test('is accepted by the macOS runtime and the session still runs', () {
      // The macOS release binary ships the CoreML EP. Parts of a graph may
      // fall back to CPU; what must hold is that D0.10's options are accepted
      // and the results are unchanged.
      final options = OrtSessionOptions(runtime)
        ..appendCoreML(CoreMlOptions(modelCacheDirectory: cache.path));
      addTearDown(options.dispose);
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(
        runtime,
        Float32List.fromList([1, 2, 3, 4]),
        [1, 4],
      );
      addTearDown(x.dispose);

      final outputs = session.run({'x': x});
      addTearDown(() => disposeAll(outputs));

      expect(outputs['y']!.toFloat32List(), [3, 5, 7, 9]);
    });

    test('rejects options after dispose', () {
      final options = OrtSessionOptions(runtime)..dispose();

      expect(
        () => options.appendCoreML(
          CoreMlOptions(modelCacheDirectory: cache.path),
        ),
        throwsStateError,
      );
    });
  });
}
