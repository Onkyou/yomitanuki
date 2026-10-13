import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the dictionary SQLite file lives on this device.
///
/// `SqliteDictionary.openFile` takes a plain path; this seam is what turns
/// the bundled asset into one. Tests build a temporary file and skip the
/// seam entirely.
abstract interface class DictionaryAsset {
  /// The path of a readable copy of the dictionary, copied from the bundle
  /// on first use and whenever the bundled version changes.
  Future<String> localPath();
}

/// The dictionary could not be provided: the asset is not in the bundle
/// (`make dict` was not run before the build) or the copy failed.
class DictionaryAssetError implements Exception {
  const DictionaryAssetError(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'DictionaryAssetError: $message';
}

/// Copies `assets/dict/dictionary.sqlite` from the Flutter asset bundle into
/// the app support directory (the sqlite3 package cannot open an asset
/// directly, D3.7). A `dictionary.version` stamp written by the build
/// script travels with the asset; the copy is redone only when the stamp
/// differs, so a normal launch costs one small asset read.
class BundledDictionaryAsset implements DictionaryAsset {
  BundledDictionaryAsset({
    AssetBundle? bundle,
    Future<Directory> Function()? supportDirectory,
    this.assetKey = 'assets/dict/dictionary.sqlite',
    this.versionKey = 'assets/dict/dictionary.version',
  }) : _bundle = bundle ?? rootBundle,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final AssetBundle _bundle;
  final Future<Directory> Function() _supportDirectory;
  final String assetKey;
  final String versionKey;

  @override
  Future<String> localPath() async {
    final dir = await _supportDirectory();
    final target = File(p.join(dir.path, p.basename(assetKey)));
    final stamp = File('${target.path}.version');
    final String version;
    try {
      version = await _bundle.loadString(versionKey, cache: false);
    } on FlutterError catch (e) {
      throw DictionaryAssetError(
        'The dictionary asset is not in the bundle; run `make dict` and rebuild.',
        e,
      );
    }
    if (target.existsSync() &&
        stamp.existsSync() &&
        stamp.readAsStringSync() == version) {
      return target.path;
    }
    try {
      final data = await _bundle.load(assetKey);
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await partial.rename(target.path);
      await stamp.writeAsString(version, flush: true);
    } on FlutterError catch (e) {
      throw DictionaryAssetError(
        'The dictionary asset is not in the bundle; run `make dict` and rebuild.',
        e,
      );
    } on IOException catch (e) {
      throw DictionaryAssetError('Copying the dictionary failed.', e);
    }
    return target.path;
  }
}
