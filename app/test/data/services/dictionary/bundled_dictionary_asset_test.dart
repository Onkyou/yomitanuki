import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/dictionary/bundled_dictionary_asset.dart';

/// An asset bundle over an in-memory map that counts loads per key.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, List<int>> files;
  final Map<String, int> loads = {};

  @override
  Future<ByteData> load(String key) async {
    loads[key] = (loads[key] ?? 0) + 1;
    final bytes = files[key];
    if (bytes == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  late Directory tmp;
  const key = 'assets/dict/dictionary.sqlite';
  const versionKey = 'assets/dict/dictionary.version';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('yomitanuki_asset_');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  BundledDictionaryAsset asset(_FakeBundle bundle) =>
      BundledDictionaryAsset(bundle: bundle, supportDirectory: () async => tmp);

  test('the first call copies the asset next to its version stamp', () async {
    final bundle = _FakeBundle({
      key: [1, 2, 3, 4],
      versionKey: 'v1'.codeUnits,
    });

    final path = await asset(bundle).localPath();

    expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
    expect(File('$path.version').readAsStringSync(), 'v1');
    expect(path, startsWith(tmp.path));
  });

  test(
    'a copy with the same version is reused without loading the asset',
    () async {
      final bundle = _FakeBundle({
        key: [1, 2, 3, 4],
        versionKey: 'v1'.codeUnits,
      });
      final first = await asset(bundle).localPath();

      final second = await asset(bundle).localPath();

      expect(second, first);
      expect(bundle.loads[key], 1);
    },
  );

  test('a new bundled version replaces the copy', () async {
    final old = _FakeBundle({
      key: [1, 2, 3, 4],
      versionKey: 'v1'.codeUnits,
    });
    final path = await asset(old).localPath();
    final updated = _FakeBundle({
      key: [9, 9],
      versionKey: 'v2'.codeUnits,
    });

    final updatedPath = await asset(updated).localPath();

    expect(updatedPath, path);
    expect(File(path).readAsBytesSync(), [9, 9]);
    expect(File('$path.version').readAsStringSync(), 'v2');
  });

  test('a missing asset is reported as DictionaryAssetError', () async {
    final bundle = _FakeBundle({});

    await expectLater(
      asset(bundle).localPath(),
      throwsA(
        isA<DictionaryAssetError>().having(
          (e) => e.message,
          'message',
          contains('make dict'),
        ),
      ),
    );
  });
}
