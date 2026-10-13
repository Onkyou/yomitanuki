import 'dart:convert';
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

/// The sha256 `make models` recorded per file in `manifest.json`; the
/// goldens name the graphs they were made with and a test refuses others
/// (`ModelAssets.prepare` hashes the files themselves at copy time).
Map<String, String> manifestSha256s(Directory models) {
  final manifest = jsonDecode(
    File('${models.path}/manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final files = manifest['files']! as Map<String, Object?>;
  return {
    for (final MapEntry(key: name, value: entry) in files.entries)
      name: (entry! as Map<String, Object?>)['sha256']! as String,
  };
}

/// Fails unless every graph [golden] names has the manifest's sha256.
void expectGoldenModels(Map<String, String> golden, Map<String, String> built) {
  for (final MapEntry(key: name, value: sha) in golden.entries) {
    if (built[name] != sha) {
      throw StateError(
        'the golden was recorded with $name ${sha.substring(0, 12)}…, '
        'assets/models/ holds ${built[name]?.substring(0, 12)}…: rebuild '
        'with `make models` or re-record the goldens',
      );
    }
  }
}

/// `app/test/goldens/`.
Directory goldensDirectory() =>
    Directory('${Directory.current.path}/test/goldens');

/// A fresh, empty directory under the system temp directory; the caller
/// deletes it.
Directory tempDirectory(String prefix) =>
    Directory.systemTemp.createTempSync('yomitanuki_$prefix');
