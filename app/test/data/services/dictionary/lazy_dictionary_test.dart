import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/dictionary/bundled_dictionary_asset.dart';
import 'package:yomitanuki/data/services/dictionary/lazy_dictionary.dart';
import 'package:yomitanuki/domain/errors.dart';

import '../../../fixtures/dict/mini_dictionary.dart';

class _Asset implements DictionaryAsset {
  _Asset(this.path, {this.failures = 0});

  final String path;
  int failures;
  int calls = 0;

  @override
  Future<String> localPath() async {
    calls++;
    if (failures > 0) {
      failures--;
      throw const DictionaryAssetError('asset missing');
    }
    return path;
  }
}

void main() {
  late Directory tmp;
  late String dbPath;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('lazy_dict');
    dbPath = '${tmp.path}/mini.sqlite';
    buildMiniDictionary(dbPath);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('opens once, even for concurrent first lookups', () async {
    final asset = _Asset(dbPath);
    final dict = LazyDictionary(asset: asset);

    final results = await Future.wait([
      dict.lookupAt('食べる', 0),
      dict.lookupAt('本', 0),
      dict.kanji('食'),
    ]);

    expect(asset.calls, 1);
    expect(results[0], isNotEmpty);
    expect(results[1], isNotEmpty);
    expect(results[2], isNotNull);
    await dict.close();
  });

  test(
    'a missing asset is a DictionaryUnavailableError and is retried',
    () async {
      final asset = _Asset(dbPath, failures: 1);
      final dict = LazyDictionary(asset: asset);

      await expectLater(
        dict.lookupAt('本', 0),
        throwsA(isA<DictionaryUnavailableError>()),
      );
      expect(await dict.lookupAt('本', 0), isNotEmpty);
      expect(asset.calls, 2);
      await dict.close();
    },
  );

  test('an unusable file is a DictionaryUnavailableError', () async {
    final bad = File('${tmp.path}/bad.sqlite')..writeAsStringSync('nope');
    final dict = LazyDictionary(asset: _Asset(bad.path));

    await expectLater(
      dict.kanji('食'),
      throwsA(isA<DictionaryUnavailableError>()),
    );
    await dict.close();
  });
}
