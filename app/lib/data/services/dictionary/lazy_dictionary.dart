import '../../../domain/errors.dart';
import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/ports/dictionary.dart';
import 'bundled_dictionary_asset.dart';
import 'sqlite_dictionary.dart';

/// Opens the SQLite dictionary on first use, behind the [DictionaryAsset]
/// seam, so app start never waits for the 56 MB asset copy (WP3 "what will
/// bite WP4"). Concurrent first calls share one open; a failed open is not
/// cached, so the next lookup tries again. [DictionaryAssetError] and
/// [DictionaryOpenError] surface as the domain's [DictionaryUnavailableError].
class LazyDictionary implements Dictionary {
  LazyDictionary({
    required DictionaryAsset asset,
    SqliteDictionary Function(String path)? open,
  }) : this._(asset, open ?? SqliteDictionary.openFile);

  LazyDictionary._(this._asset, this._open);

  final DictionaryAsset _asset;
  final SqliteDictionary Function(String path) _open;
  Future<SqliteDictionary>? _opening;

  Future<SqliteDictionary> _dictionary() {
    final inFlight = _opening;
    if (inFlight != null) {
      return inFlight;
    }
    final opening = _openNow();
    _opening = opening;
    return opening.catchError((Object e, StackTrace s) {
      _opening = null;
      return Future<SqliteDictionary>.error(e, s);
    });
  }

  Future<SqliteDictionary> _openNow() async {
    try {
      return _open(await _asset.localPath());
    } on DictionaryAssetError catch (e) {
      throw DictionaryUnavailableError(e.toString());
    } on DictionaryOpenError catch (e) {
      throw DictionaryUnavailableError(e.toString());
    }
  }

  @override
  Future<List<LookupResult>> lookupAt(String text, int index) async =>
      (await _dictionary()).lookupAt(text, index);

  @override
  Future<KanjiEntry?> kanji(String literal) async =>
      (await _dictionary()).kanji(literal);

  /// Closes the database if it was ever opened.
  Future<void> close() async {
    final opening = _opening;
    if (opening == null) {
      return;
    }
    _opening = null;
    try {
      (await opening).close();
    } on DictionaryUnavailableError {
      // Never opened; nothing to close.
    }
  }
}
