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
        // WP0b: without it ORT 1.31 places a dynamic-shape Gather on CoreML
        // and every run with zero detections fails.
        'RequireStaticInputShapes': '1',
      });
    });

    test('requireStaticInputShapes can be switched off', () {
      expect(
        const CoreMlOptions(
          modelCacheDirectory: 'd',
          requireStaticInputShapes: false,
        ).providerOptions,
        containsPair('RequireStaticInputShapes', '0'),
      );
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

    test('compiles a static-shape graph on the macOS runtime', () {
      // The macOS release binary ships the CoreML EP. D0.10's options must be
      // accepted, the results unchanged, and the cache directory populated:
      // that last check is what proves CoreML compiled the graph.
      final options = OrtSessionOptions(runtime)
        ..appendCoreML(
          CoreMlOptions(
            modelCacheDirectory: cache.path,
            requireStaticInputShapes: true,
          ),
        );
      addTearDown(options.dispose);
      final session = OrtSession.fromFile(
        fixturePath('affine_static'),
        options,
      );
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
      expect(
        cache.listSync(recursive: true),
        isNotEmpty,
        reason: 'the CoreML EP compiled the graph into ModelCacheDirectory',
      );
    });

    test('leaves a dynamic-shape graph on the CPU under the defaults', () {
      // RequireStaticInputShapes=1: the [1, n] input keeps CoreML out, the
      // CPU provider runs the graph, nothing is compiled or cached, no error.
      final options = OrtSessionOptions(runtime)
        ..appendCoreML(CoreMlOptions(modelCacheDirectory: cache.path));
      addTearDown(options.dispose);
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(runtime, Float32List.fromList([5]), [
        1,
        1,
      ]);
      addTearDown(x.dispose);

      final outputs = session.run({'x': x});
      addTearDown(() => disposeAll(outputs));

      expect(outputs['y']!.toFloat32List(), [11]);
      expect(cache.listSync(recursive: true), isEmpty);
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
