import 'package:sqlite3/sqlite3.dart';

class DictionaryBuildStats {
  const DictionaryBuildStats({
    required this.entries,
    required this.senses,
    required this.forms,
    required this.kanji,
  });

  final int entries;
  final int senses;
  final int forms;
  final int kanji;
}

class DictBuilder {
  static const int schemaVersion = 1;

  static DictionaryBuildStats build({
    required Map<String, Object?> jmdict,
    required Map<String, Object?> kanjidic,
    required String outPath,
    Map<String, String> meta = const {},
  }) {
    sqlite3.open(outPath).close();
    return const DictionaryBuildStats(
      entries: 0,
      senses: 0,
      forms: 0,
      kanji: 0,
    );
  }
}
