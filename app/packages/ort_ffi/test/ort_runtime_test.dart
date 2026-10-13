import 'package:flutter_test/flutter_test.dart';
import 'package:ort_ffi/ort_ffi.dart';

import 'support/ort_test_env.dart';

void main() {
  group('OrtRuntime.open', () {
    test('reports the linked ONNX Runtime version', () {
      final runtime = OrtRuntime.open(ortLibraryPath());
      addTearDown(runtime.dispose);

      expect(runtime.version, '1.31.0');
    });

    test('requests the API version both linked runtimes provide', () {
      // 1.30.0 on iOS (the newest onnxruntime-c pod), 1.31.0 on macOS; the
      // OrtApi struct is append-only, so the lower version is valid for both.
      expect(OrtRuntime.apiVersion, 30);
    });

    test('throws OrtException when the library cannot be loaded', () {
      expect(
        () => OrtRuntime.open('/nonexistent/libonnxruntime.dylib'),
        throwsA(
          isA<OrtException>().having(
            (e) => e.message,
            'message',
            contains('/nonexistent/libonnxruntime.dylib'),
          ),
        ),
      );
    });

    test('dispose is idempotent and use after dispose is a StateError', () {
      final runtime = OrtRuntime.open(ortLibraryPath());

      runtime.dispose();
      runtime.dispose();

      expect(() => OrtSessionOptions(runtime), throwsStateError);
    });
  });
}
