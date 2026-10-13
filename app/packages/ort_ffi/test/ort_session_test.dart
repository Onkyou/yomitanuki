import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';

import 'support/ort_test_env.dart';

void main() {
  late OrtRuntime runtime;
  late OrtSessionOptions options;

  setUp(() {
    runtime = OrtRuntime.open(ortLibraryPath());
    options = OrtSessionOptions(runtime)
      ..setIntraOpThreads(1)
      ..setGraphOptimizationLevel(OrtGraphOptimizationLevel.all);
  });

  tearDown(() {
    options.dispose();
    runtime.dispose();
  });

  group('OrtSession.fromFile', () {
    test('exposes input and output names and tensor info', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);

      expect(session.inputNames, ['x']);
      expect(session.outputNames, ['y']);
      final x = session.inputInfo.single;
      expect(x.name, 'x');
      expect(x.elementType, OrtElementType.float32);
      expect(x.shape, [1, -1], reason: 'the second dimension is symbolic');
      final y = session.outputInfo.single;
      expect(y.name, 'y');
      expect(y.elementType, OrtElementType.float32);
      expect(y.shape, [1, -1]);
    });

    test('lists every input of a multi-input graph with its dtype', () {
      final session = OrtSession.fromFile(fixturePath('ids'), options);
      addTearDown(session.dispose);

      expect(session.inputNames, ['ids', 'offset']);
      expect(session.inputInfo.map((i) => i.elementType), [
        OrtElementType.int64,
        OrtElementType.int64,
      ]);
      expect(session.inputInfo.map((i) => i.shape), [
        [1, -1],
        [1],
      ]);
    });

    test('throws OrtException with the ORT message for a missing file', () {
      expect(
        () => OrtSession.fromFile('/nonexistent/model.onnx', options),
        throwsA(
          isA<OrtException>()
              .having((e) => e.code, 'code', OrtErrorCode.noSuchFile)
              .having((e) => e.message, 'message', contains('model.onnx')),
        ),
      );
    });

    test('refuses a graph whose output is one of its inputs', () {
      // ORT returns the input value itself for such an output, so the result
      // would alias the caller's buffer and die with the input (D2.12).
      expect(
        () => OrtSession.fromFile(fixturePath('passthrough'), options),
        throwsA(
          isA<OrtException>()
              .having((e) => e.code, 'code', OrtErrorCode.invalidGraph)
              .having((e) => e.message, 'message', contains("'x'")),
        ),
      );
    });

    test('dispose is idempotent and use after dispose is a StateError', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);

      session.dispose();
      session.dispose();

      expect(() => session.run({}), throwsStateError);
    });
  });

  group('OrtSession.run', () {
    test('computes y = 2x + 1 on float32', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(runtime, Float32List.fromList([1, 2, 3]), [
        1,
        3,
      ]);
      addTearDown(x.dispose);

      final outputs = session.run({'x': x});
      addTearDown(() => disposeAll(outputs));

      expect(outputs.keys, ['y']);
      final y = outputs['y']!;
      expect(y.elementType, OrtElementType.float32);
      expect(y.shape, [1, 3]);
      expect(y.toFloat32List(), [3, 5, 7]);
    });

    test('casts uint8 pixels to float32 / 255', () {
      final session = OrtSession.fromFile(fixturePath('cast'), options);
      addTearDown(session.dispose);
      final pixels = OrtValue.fromUint8(
        runtime,
        Uint8List.fromList([0, 51, 102, 153, 204, 255, 0, 0, 0, 255, 255, 255]),
        [1, 2, 2, 3],
      );
      addTearDown(pixels.dispose);

      final outputs = session.run({'pixels': pixels});
      addTearDown(() => disposeAll(outputs));

      final norm = outputs['norm']!;
      expect(norm.shape, [1, 2, 2, 3]);
      expect(
        norm.toFloat32List(),
        [
          0,
          0.2,
          0.4,
          0.6,
          0.8,
          1,
          0,
          0,
          0,
          1,
          1,
          1,
        ].map((v) => closeTo(v, 1e-6)),
      );
    });

    test('adds int64 ids and offset', () {
      final session = OrtSession.fromFile(fixturePath('ids'), options);
      addTearDown(session.dispose);
      final ids = OrtValue.fromInt64(
        runtime,
        Int64List.fromList([2, 4, 6054]),
        [1, 3],
      );
      final offset = OrtValue.fromInt64(runtime, Int64List.fromList([3]), [1]);
      addTearDown(ids.dispose);
      addTearDown(offset.dispose);

      final outputs = session.run({'ids': ids, 'offset': offset});
      addTearDown(() => disposeAll(outputs));

      final shifted = outputs['shifted']!;
      expect(shifted.elementType, OrtElementType.int64);
      expect(shifted.shape, [1, 3]);
      expect(shifted.toInt64List(), [5, 7, 6057]);
    });

    test('returns only the requested outputs when outputNames is given', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(runtime, Float32List.fromList([0]), [
        1,
        1,
      ]);
      addTearDown(x.dispose);

      final outputs = session.run({'x': x}, outputNames: ['y']);
      addTearDown(() => disposeAll(outputs));

      expect(outputs['y']!.toFloat32List(), [1]);
    });

    test('throws OrtException naming a wrong input name', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(runtime, Float32List.fromList([1]), [
        1,
        1,
      ]);
      addTearDown(x.dispose);

      expect(
        () => session.run({'nope': x}),
        throwsA(
          isA<OrtException>()
              .having((e) => e.code, 'code', OrtErrorCode.invalidArgument)
              .having((e) => e.message, 'message', contains('nope')),
        ),
      );
    });

    test('throws OrtException when a required input is missing', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);

      expect(
        () => session.run({}),
        throwsA(
          isA<OrtException>().having(
            (e) => e.message,
            'message',
            contains('x'),
          ),
        ),
      );
    });

    test('rejects duplicate output names with ArgumentError', () {
      // Two fetches of one output would be two OrtValues under one key; the
      // second would leak.
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(runtime, Float32List.fromList([1]), [
        1,
        1,
      ]);
      addTearDown(x.dispose);

      expect(
        () => session.run({'x': x}, outputNames: ['y', 'y']),
        throwsArgumentError,
      );
    });

    test('throws OrtException for an unknown output name', () {
      final session = OrtSession.fromFile(fixturePath('affine'), options);
      addTearDown(session.dispose);
      final x = OrtValue.fromFloat32(runtime, Float32List.fromList([1]), [
        1,
        1,
      ]);
      addTearDown(x.dispose);

      expect(
        () => session.run({'x': x}, outputNames: ['nope']),
        throwsA(isA<OrtException>()),
      );
    });
  });
}
