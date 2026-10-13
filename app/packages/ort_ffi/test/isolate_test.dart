import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';

import 'support/ort_test_env.dart';

void main() {
  test(
    'a background isolate opens the runtime, runs and returns results',
    () async {
      // The pattern WP2b's adapters use: the worker isolate owns the runtime,
      // the session and every value; only plain Dart data crosses isolates.
      final libraryPath = ortLibraryPath();
      final modelPath = fixturePath('affine');

      final result = await Isolate.run(() {
        final runtime = OrtRuntime.open(libraryPath);
        final options = OrtSessionOptions(runtime);
        final session = OrtSession.fromFile(modelPath, options);
        final x = OrtValue.fromFloat32(
          runtime,
          Float32List.fromList([10, 20]),
          [1, 2],
        );
        final outputs = session.run({'x': x});
        final y = outputs['y']!.toFloat32List();
        outputs.values.forEach((v) => v.dispose());
        x.dispose();
        session.dispose();
        options.dispose();
        runtime.dispose();
        return y;
      });

      expect(result, [21, 41]);
    },
  );
}
