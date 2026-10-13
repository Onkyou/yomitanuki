import 'dart:convert';
import 'dart:io';

import 'package:yomitanuki/data/services/dictionary/dict_builder.dart';

/// The committed mini JMdict/KANJIDIC2 fixtures (real jmdict-simplified
/// schema, a few dozen hand-picked entries). Paths are relative to `app/`,
/// where `flutter test` runs.
const miniJmdictPath = 'test/fixtures/dict/mini_jmdict.json';
const miniKanjidicPath = 'test/fixtures/dict/mini_kanjidic.json';

/// Builds the mini dictionary into [outPath] with the production builder.
DictionaryBuildStats buildMiniDictionary(
  String outPath, {
  Map<String, String> meta = const {},
}) {
  Map<String, Object?> load(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return DictBuilder.build(
    jmdict: load(miniJmdictPath),
    kanjidic: load(miniKanjidicPath),
    outPath: outPath,
    meta: meta,
  );
}
