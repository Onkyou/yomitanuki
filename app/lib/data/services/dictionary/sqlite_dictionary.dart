import 'package:sqlite3/sqlite3.dart';

import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/ports/dictionary.dart';

class SqliteDictionary implements Dictionary {
  SqliteDictionary._(this._db);

  static const int maxSurfaceUnits = 24;

  final Database _db;

  static SqliteDictionary openFile(String path) =>
      SqliteDictionary._(sqlite3.open(path, mode: OpenMode.readOnly));

  Map<String, String> get meta => const {};

  void close() => _db.close();

  @override
  Future<List<LookupResult>> lookupAt(String text, int index) async => const [];

  @override
  Future<KanjiEntry?> kanji(String literal) async => null;
}
