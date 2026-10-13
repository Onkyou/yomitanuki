import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';

import 'support/ort_test_env.dart';

void main() {
  late OrtRuntime runtime;

  setUp(() => runtime = OrtRuntime.open(ortLibraryPath()));
  tearDown(() => runtime.dispose());

  group('OrtValue', () {
    test('round-trips float32 with its shape', () {
      final value = OrtValue.fromFloat32(
        runtime,
        Float32List.fromList([1.5, -2, 3]),
        [3],
      );
      addTearDown(value.dispose);

      expect(value.elementType, OrtElementType.float32);
      expect(value.shape, [3]);
      expect(value.toFloat32List(), [1.5, -2, 3]);
    });

    test('readFloat32 copies one bounds-checked window', () {
      final value = OrtValue.fromFloat32(
        runtime,
        Float32List.fromList([0, 1, 2, 3, 4, 5]),
        [1, 2, 3],
      );
      addTearDown(value.dispose);

      expect(value.readFloat32(offset: 3), [3, 4, 5]);
      expect(value.readFloat32(offset: 1, count: 2), [1, 2]);
      expect(value.readFloat32(offset: 6, count: 0), isEmpty);
      expect(value.readFloat32(), [0, 1, 2, 3, 4, 5]);
      expect(() => value.readFloat32(offset: 4, count: 3), throwsRangeError);
      expect(() => value.readFloat32(offset: -1), throwsRangeError);
      expect(() => value.readFloat32(offset: 7), throwsRangeError);
    });

    test('readFloat32 on a uint8 tensor is a StateError', () {
      final value = OrtValue.fromUint8(runtime, Uint8List.fromList([1]), [1]);
      addTearDown(value.dispose);

      expect(value.readFloat32, throwsStateError);
    });

    test('round-trips uint8 with a 4-D shape', () {
      final value = OrtValue.fromUint8(
        runtime,
        Uint8List.fromList([0, 1, 2, 3, 4, 5]),
        [1, 1, 2, 3],
      );
      addTearDown(value.dispose);

      expect(value.elementType, OrtElementType.uint8);
      expect(value.shape, [1, 1, 2, 3]);
      expect(value.toUint8List(), [0, 1, 2, 3, 4, 5]);
    });

    test('round-trips int64', () {
      final value = OrtValue.fromInt64(
        runtime,
        Int64List.fromList([-1, 1 << 40]),
        [2],
      );
      addTearDown(value.dispose);

      expect(value.elementType, OrtElementType.int64);
      expect(value.toInt64List(), [-1, 1 << 40]);
    });

    test('copies the caller buffer: later writes do not reach the tensor', () {
      final data = Float32List.fromList([1, 2]);
      final value = OrtValue.fromFloat32(runtime, data, [2]);
      addTearDown(value.dispose);

      data[0] = 99;

      expect(value.toFloat32List(), [1, 2]);
    });

    test('rejects a shape that does not match the data length', () {
      expect(
        () => OrtValue.fromFloat32(runtime, Float32List(6), [2, 2]),
        throwsArgumentError,
      );
      // Product 4 matches the data, so only the per-dimension check rejects it.
      expect(
        () => OrtValue.fromUint8(runtime, Uint8List(4), [-1, -4]),
        throwsArgumentError,
      );
    });

    test('reading as the wrong element type is a StateError', () {
      final value = OrtValue.fromInt64(runtime, Int64List.fromList([1]), [1]);
      addTearDown(value.dispose);

      expect(value.toFloat32List, throwsStateError);
      expect(value.toUint8List, throwsStateError);
    });

    test('dispose is idempotent and use after dispose is a StateError', () {
      final value = OrtValue.fromUint8(runtime, Uint8List(1), [1]);

      value.dispose();
      value.dispose();

      expect(value.toUint8List, throwsStateError);
    });
  });
}
