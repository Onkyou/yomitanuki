import 'dart:io';

/// Where the real-inference tests find the macOS ONNX Runtime and the built
/// graphs. `flutter test` runs with `app/` as the working directory.
///
/// `make ort-macos` fetches the dylib (sha256 pinned in the Makefile) and
/// `make models` builds the graphs; `make gate-test` runs both first.

/// The dylib `make ort-macos` fetches. `ORT_DYLIB` overrides the location.
String ortLibraryPath() {
  final fromEnv = Platform.environment['ORT_DYLIB'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final path =
      '${Directory.current.path}/packages/ort_ffi/tool/ort/lib/'
      'libonnxruntime.1.31.0.dylib';
  if (!File(path).existsSync()) {
    throw StateError(
      '$path is missing: run `make ort-macos` from the repository root.',
    );
  }
  return path;
}

/// `app/assets/models/`, as `make models` leaves it.
Directory modelDirectory() {
  final directory = Directory('${Directory.current.path}/assets/models');
  if (!File('${directory.path}/manifest.json').existsSync()) {
    throw StateError(
      '${directory.path}/manifest.json is missing: run `make models` from '
      'the repository root.',
    );
  }
  return directory;
}

/// `app/test/goldens/`.
Directory goldensDirectory() =>
    Directory('${Directory.current.path}/test/goldens');

/// A fresh, empty directory under the system temp directory; the caller
/// deletes it.
Directory tempDirectory(String prefix) =>
    Directory.systemTemp.createTempSync('yomitanuki_$prefix');
