import 'dart:io';

/// The macOS ONNX Runtime dylib that `make ort-macos` fetches (sha256 pinned
/// in the Makefile). `ORT_DYLIB` overrides the location.
String ortLibraryPath() {
  final fromEnv = Platform.environment['ORT_DYLIB'];
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv;
  }
  final path =
      '${Directory.current.path}/tool/ort/lib/libonnxruntime.1.31.0.dylib';
  if (!File(path).existsSync()) {
    throw StateError(
      '$path is missing: run `make ort-macos` from the repository root.',
    );
  }
  return path;
}

/// One of the graphs tool/make_fixtures.py writes.
String fixturePath(String name) =>
    '${Directory.current.path}/test/fixtures/$name.onnx';
