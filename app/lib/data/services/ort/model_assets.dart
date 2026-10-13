import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// The ONNX graphs and the vocabulary as files on disk, where ONNX Runtime
/// can open them (WP2b task 4).
///
/// The bundle holds `assets/models/` (D6; built by `make models`, see
/// `manifest.json` there). ORT needs paths, so [prepare] copies the four
/// files into [directory] once and stamps the copy with the bundle's
/// `manifest.json`; a later run compares the stamped sha256s with the
/// bundle's and recopies when they differ or a file is missing or has the
/// wrong size. The bundle and the directory are injected, so the copy is
/// tested with a fake bundle and a temp directory.
class ModelAssets {
  /// Files already in [directory] (the test goldens, or a prepared copy).
  ModelAssets.inDirectory(Directory directory) : directory = directory.path;

  /// The files `make models` writes next to `manifest.json`.
  static const List<String> fileNames = [
    'detector.onnx',
    'ocr_encoder.onnx',
    'ocr_decoder.onnx',
    'vocab.txt',
  ];

  /// The asset key prefix declared in `pubspec.yaml`.
  static const String bundlePrefix = 'assets/models/';

  static const String _manifest = 'manifest.json';

  /// Where the files are.
  final String directory;

  String get detectorPath => '$directory/detector.onnx';
  String get encoderPath => '$directory/ocr_encoder.onnx';
  String get decoderPath => '$directory/ocr_decoder.onnx';
  String get vocabPath => '$directory/vocab.txt';

  /// `<application support>/models`, the directory the app prepares into.
  /// Application support is not backed up to iCloud and not visible in the
  /// Files app, and the CoreML cache goes next to it (`coreMlCacheDirectory`).
  static Future<Directory> defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/models');
  }

  /// A writable cache directory for the CoreML execution provider
  /// (WP0 D0.10), beside the model files.
  String get coreMlCacheDirectory => '$directory/coreml_cache';

  /// Copies the models out of [bundle] into [directory] unless the stamp
  /// there already matches the bundle's manifest. Throws
  /// [ModelAssetsException] when the bundle lacks a file, a copied file does
  /// not hash to what the manifest says, or the directory cannot be written.
  ///
  /// Concurrent calls for the same directory share one copy (the in-flight
  /// future is memoised per path until it completes); callers from
  /// different directories proceed independently.
  static Future<ModelAssets> prepare({
    required AssetBundle bundle,
    required Directory directory,
  }) {
    final key = directory.absolute.path;
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    final preparing = _prepare(bundle, directory).whenComplete(() {
      // `remove` returns the future itself; returning it from here would
      // make `whenComplete` wait on itself, so it is dropped on purpose.
      unawaited(_inFlight.remove(key));
    });
    _inFlight[key] = preparing;
    return preparing;
  }

  static final Map<String, Future<ModelAssets>> _inFlight = {};
  static int _copySequence = 0;

  static Future<ModelAssets> _prepare(
    AssetBundle bundle,
    Directory directory,
  ) async {
    final manifestJson = await _loadBundle(bundle, _manifest);
    final wanted = _ManifestFiles.parse(utf8.decode(manifestJson));
    try {
      if (await _stampMatches(directory, wanted)) {
        return ModelAssets.inDirectory(directory);
      }
      await directory.create(recursive: true);
      for (final name in fileNames) {
        final entry = wanted.entries[name];
        if (entry == null) {
          throw ModelAssetsException('$_manifest in the bundle lacks $name');
        }
        await _copyVerified(bundle, name, entry, directory);
      }
      // Last, so an interrupted copy is redone on the next start.
      await File('${directory.path}/$_manifest').writeAsBytes(manifestJson);
    } on FileSystemException catch (e) {
      throw ModelAssetsException(
        'could not write the models to ${directory.path}: ${e.message}'
        '${e.osError == null ? '' : ' (${e.osError})'}',
      );
    }
    return ModelAssets.inDirectory(directory);
  }

  static Future<bool> _stampMatches(
    Directory directory,
    _ManifestFiles wanted,
  ) async {
    final stamp = File('${directory.path}/$_manifest');
    if (!await stamp.exists()) return false;
    final _ManifestFiles stamped;
    try {
      stamped = _ManifestFiles.parse(await stamp.readAsString());
    } on FormatException {
      return false;
    }
    for (final name in fileNames) {
      final entry = wanted.entries[name];
      if (entry == null || stamped.entries[name]?.sha256 != entry.sha256) {
        return false;
      }
      final file = File('${directory.path}/$name');
      if (!await file.exists() || await file.length() != entry.bytes) {
        return false;
      }
    }
    return true;
  }

  static Future<void> _copyVerified(
    AssetBundle bundle,
    String name,
    _ManifestEntry entry,
    Directory directory,
  ) async {
    final bytes = await _loadBundle(bundle, name);
    // A name no other process or in-flight copy uses, so two copies into the
    // same directory (two app instances, or two prepare() calls before the
    // memoisation could join them) never clobber each other's partial file;
    // the final rename is atomic.
    final partial = File(
      '${directory.path}/$name.$pid.${_copySequence++}.partial',
    );
    await partial.writeAsBytes(bytes, flush: true);
    // Hashing 87 MB blocks for a noticeable time; the worker isolate reads
    // the file back rather than receiving a copy of the bytes.
    final path = partial.path;
    final digest = await Isolate.run(
      () => sha256.convert(File(path).readAsBytesSync()).toString(),
    );
    if (digest != entry.sha256) {
      await partial.delete();
      throw ModelAssetsException(
        '$name in the bundle hashes to $digest, '
        '$_manifest says ${entry.sha256}',
      );
    }
    await partial.rename('${directory.path}/$name');
  }

  static Future<List<int>> _loadBundle(AssetBundle bundle, String name) async {
    final ByteData data;
    try {
      data = await bundle.load('$bundlePrefix$name');
    } on FlutterError catch (e) {
      throw ModelAssetsException(
        '$bundlePrefix$name is not in the bundle (run `make models` before '
        'building): ${e.message}',
      );
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// The bundle's models are missing or do not match their manifest: the
/// build shipped a broken `assets/models/`, nothing the app can recover from.
class ModelAssetsException implements Exception {
  ModelAssetsException(this.message);

  final String message;

  @override
  String toString() => 'ModelAssetsException: $message';
}

class _ManifestEntry {
  const _ManifestEntry({required this.sha256, required this.bytes});

  final String sha256;
  final int bytes;
}

/// The `files` section of `manifest.json`.
class _ManifestFiles {
  const _ManifestFiles(this.entries);

  /// Throws [FormatException] on anything that is not that section.
  factory _ManifestFiles.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      rethrow;
    }
    if (decoded case {'files': final Map<String, Object?> files}) {
      return _ManifestFiles({
        for (final MapEntry(key: name, value: entry) in files.entries)
          if (entry case {
            'sha256': final String sha256,
            'bytes': final int bytes,
          })
            name: _ManifestEntry(sha256: sha256, bytes: bytes),
      });
    }
    throw const FormatException('manifest.json has no "files" section');
  }

  final Map<String, _ManifestEntry> entries;
}
