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

  test(
    'a stamp differing only in the content hash triggers a recopy',
    () async {
      const pins = 'jmdict 3.6.2+x kanjidic 3.6.2+x schema 1';
      final old = _FakeBundle({
        key: [1, 2, 3, 4],
        versionKey: '$pins sha256 aaaa'.codeUnits,
      });
      final path = await asset(old).localPath();
      final rebuilt = _FakeBundle({
        key: [5, 6],
        versionKey: '$pins sha256 bbbb'.codeUnits,
      });

      await asset(rebuilt).localPath();

      expect(File(path).readAsBytesSync(), [5, 6]);
      expect(rebuilt.loads[key], 1);
    },
  );

  test('a copy that fails after the version loaded leaves no stamp', () async {
    final bundle = _FakeBundle({versionKey: 'v1'.codeUnits});

    await expectLater(
      asset(bundle).localPath(),
      throwsA(isA<DictionaryAssetError>()),
    );

    expect(tmp.listSync().where((f) => f.path.endsWith('.version')), isEmpty);
    expect(tmp.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
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
