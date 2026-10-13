import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/ort/model_assets.dart';

import '../../../fakes/fake_asset_bundle.dart';
import '../../../support/ort_test_env.dart';

void main() {
  late Directory target;

  setUp(() => target = tempDirectory('model_assets_'));
  tearDown(() => target.deleteSync(recursive: true));

  /// A bundle whose four model files hold [contents] and whose manifest
  /// records their real sha256 and size, unless [manifestOverrides] lies.
  FakeAssetBundle bundle({
    Map<String, String> contents = const {},
    Map<String, String> manifestOverrides = const {},
  }) {
    final files = <String, Uint8List>{
      for (final name in ModelAssets.fileNames)
        name: utf8.encode(contents[name] ?? 'bytes of $name'),
    };
    final manifest = {
      'files': {
        for (final MapEntry(key: name, value: bytes) in files.entries)
          name: {
            'sha256':
                manifestOverrides[name] ?? sha256.convert(bytes).toString(),
            'bytes': bytes.length,
          },
      },
    };
    return FakeAssetBundle({
      for (final MapEntry(key: name, value: bytes) in files.entries)
        '${ModelAssets.bundlePrefix}$name': bytes,
      '${ModelAssets.bundlePrefix}manifest.json': utf8.encode(
        jsonEncode(manifest),
      ),
    });
  }

  String read(String name) => File('${target.path}/$name').readAsStringSync();

  test('first run copies every file out of the bundle and stamps it', () async {
    final assets = await ModelAssets.prepare(
      bundle: bundle(),
      directory: target,
    );

    expect(assets.directory, target.path);
    expect(assets.detectorPath, '${target.path}/detector.onnx');
    expect(assets.encoderPath, '${target.path}/ocr_encoder.onnx');
    expect(assets.decoderPath, '${target.path}/ocr_decoder.onnx');
    expect(assets.vocabPath, '${target.path}/vocab.txt');
    for (final name in ModelAssets.fileNames) {
      expect(read(name), 'bytes of $name');
    }
    expect(File('${target.path}/manifest.json').existsSync(), isTrue);
  });

  test('a second run with the same manifest reads no model bytes', () async {
    await ModelAssets.prepare(bundle: bundle(), directory: target);
    final again = bundle();

    await ModelAssets.prepare(bundle: again, directory: target);

    expect(again.loaded, ['${ModelAssets.bundlePrefix}manifest.json']);
  });

  test('a changed sha256 in the bundle manifest recopies', () async {
    await ModelAssets.prepare(bundle: bundle(), directory: target);
    final updated = bundle(contents: {'vocab.txt': 'new vocabulary'});

    await ModelAssets.prepare(bundle: updated, directory: target);

    expect(read('vocab.txt'), 'new vocabulary');
    expect(updated.loaded, contains('${ModelAssets.bundlePrefix}vocab.txt'));
  });

  test('a stamped directory missing a file recopies', () async {
    await ModelAssets.prepare(bundle: bundle(), directory: target);
    File('${target.path}/ocr_decoder.onnx').deleteSync();
    final again = bundle();

    await ModelAssets.prepare(bundle: again, directory: target);

    expect(read('ocr_decoder.onnx'), 'bytes of ocr_decoder.onnx');
  });

  test('a stamped file of the wrong size recopies', () async {
    await ModelAssets.prepare(bundle: bundle(), directory: target);
    File('${target.path}/detector.onnx').writeAsStringSync('truncated');

    await ModelAssets.prepare(bundle: bundle(), directory: target);

    expect(read('detector.onnx'), 'bytes of detector.onnx');
  });

  test(
    'bundle bytes that do not hash to the manifest are refused, unstamped',
    () async {
      final lying = bundle(manifestOverrides: {'detector.onnx': 'f' * 64});

      await expectLater(
        ModelAssets.prepare(bundle: lying, directory: target),
        throwsA(
          isA<ModelAssetsException>().having(
            (e) => e.message,
            'message',
            contains('detector.onnx'),
          ),
        ),
      );
      expect(File('${target.path}/manifest.json').existsSync(), isFalse);
    },
  );

  test('a bundle without the models is a ModelAssetsException', () async {
    final empty = FakeAssetBundle({});

    await expectLater(
      ModelAssets.prepare(bundle: empty, directory: target),
      throwsA(isA<ModelAssetsException>()),
    );
  });

  test('inDirectory points at files that are already there', () {
    final assets = ModelAssets.inDirectory(modelDirectory());

    expect(File(assets.detectorPath).existsSync(), isTrue);
    expect(File(assets.vocabPath).existsSync(), isTrue);
  });
}
