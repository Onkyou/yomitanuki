import 'package:sqlite3/sqlite3.dart';

import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/ports/dictionary.dart';
import '../../../domain/text/lookup_breaks.dart';
import 'deinflector.dart';
import 'dict_builder.dart';
import 'kana.dart';

/// The file given to [SqliteDictionary.openFile] is not a usable dictionary:
/// missing, unreadable, not SQLite, or built with another schema version.
class DictionaryOpenError implements Exception {
  const DictionaryOpenError(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'DictionaryOpenError: $message';
}

/// JMdict + KANJIDIC2 lookups over the SQLite file `DictBuilder` writes.
///
/// `lookupAt` scans from the tapped character (WP0 C15): every surface
/// from [maxSurfaceUnits] code units down to one is deinflected, each
/// candidate base is looked up in `forms`, and an entry is kept when its
/// POS tags are compatible with the deinflection that produced it. Results
/// come longest surface first, then common entries first.
///
/// Opening is synchronous and takes a plain file path, so tests open a
/// temporary build directly; the asset copy lives in
/// `BundledDictionaryAsset` behind the `DictionaryAsset` seam.
class SqliteDictionary implements Dictionary {
  /// Prepares every query and reads `meta`; throws [DictionaryOpenError]
  /// when the file is not a dictionary of this schema version.
  factory SqliteDictionary._open(Database db) {
    final SqliteDictionary dict;
    try {
      dict = SqliteDictionary._(db);
    } on SqliteException catch (e) {
      db.close();
      throw DictionaryOpenError('not a dictionary database', e);
    }
    final schema = dict.meta['schema_version'];
    if (schema != '${DictBuilder.schemaVersion}') {
      dict.close();
      throw DictionaryOpenError(
        'schema version $schema, expected ${DictBuilder.schemaVersion}',
      );
    }
    return dict;
  }

  SqliteDictionary._(this._db)
    : _formsByKey = _db.prepare(
        'SELECT entry_id, reading FROM forms WHERE form = ? ORDER BY rowid',
      ),
      _entryById = _db.prepare(
        'SELECT headword, reading, is_common FROM entries WHERE id = ?',
      ),
      _sensesByEntry = _db.prepare(
        'SELECT glosses, pos FROM senses WHERE entry_id = ? ORDER BY seq',
      ),
      _kanjiByLiteral = _db.prepare(
        'SELECT meanings, on_readings, kun_readings, strokes, grade, jlpt '
        'FROM kanji WHERE literal = ?',
      ),
      meta = {
        for (final row in _db.select('SELECT key, value FROM meta'))
          row['key'] as String: row['value'] as String,
      };

  /// Longest surface tried, in UTF-16 code units (D3.5).
  static const int maxSurfaceUnits = 24;

  static const _deinflector = Deinflector();

  final Database _db;
  final PreparedStatement _formsByKey;
  final PreparedStatement _entryById;
  final PreparedStatement _sensesByEntry;
  final PreparedStatement _kanjiByLiteral;

  /// The `meta` table: source versions, dates and the licence text.
  final Map<String, String> meta;

  /// Opens the SQLite file at [path] read-only and prepares every query.
  /// Throws [DictionaryOpenError] when the file is missing, unreadable, not
  /// SQLite, or not this schema version.
  static SqliteDictionary openFile(String path) {
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      throw DictionaryOpenError('cannot open $path', e);
    }
    return SqliteDictionary._open(db);
  }

  void close() {
    _formsByKey.close();
    _entryById.close();
    _sensesByEntry.close();
    _kanjiByLiteral.close();
    _db.close();
  }

  @override
  Future<List<LookupResult>> lookupAt(String text, int index) async =>
      lookupAtSync(text, index);

  /// The synchronous body of [lookupAt]; the port is async by contract and
  /// the work is small enough to stay on the caller's isolate (D3.6).
  List<LookupResult> lookupAtSync(String text, int index) {
    final start = _clampToBoundary(text, index.clamp(0, text.length));
    final ends = _surfaceEnds(text, start);
    final results = <LookupResult>[];
    final entries = <int, DictionaryEntry?>{};
    for (final end in ends.reversed) {
      final surface = text.substring(start, end);
      results.addAll(_lookupSurface(surface, start, entries));
    }
    return results;
  }

  /// Every match for one surface, one result per entry: common entries
  /// first, then entries whose headword or reading is the matched base
  /// (本 【ほん】 before 本 as a spelling of 元 【もと】, 来る before 凝る for
  /// こられる), then shorter deinflection chains, then by entry id.
  List<LookupResult> _lookupSurface(
    String surface,
    int start,
    Map<int, DictionaryEntry?> entries,
  ) {
    final normalised = toHiragana(surface);
    final seen = <int>{};
    final matches = <LookupResult>[];
    for (final d in _deinflector.deinflect(normalised)) {
      final base = d.reasons.isEmpty ? surface : d.base;
      for (final (id, reading) in _formMatches(d.base)) {
        if (seen.contains(id)) {
          continue;
        }
        final entry = _entry(id, entries);
        if (entry == null || !d.acceptsPos(_pos(entry))) {
          continue;
        }
        seen.add(id);
        matches.add(_result(surface, start, base, reading, d.reasons, entry));
      }
      // A conjugated Xする has no entry of its own; X is a noun tagged vs.
      if (d.classes & WordClass.vs.bit != 0 &&
          d.base.length > 2 &&
          d.base.endsWith('する')) {
        final noun = d.base.substring(0, d.base.length - 2);
        for (final (id, reading) in _formMatches(noun)) {
          if (seen.contains(id)) {
            continue;
          }
          final entry = _entry(id, entries);
          if (entry == null || !_pos(entry).contains('vs')) {
            continue;
          }
          seen.add(id);
          matches.add(_result(surface, start, noun, reading, d.reasons, entry));
        }
      }
    }
    matches.sort((a, b) {
      if (a.entry.isCommon != b.entry.isCommon) {
        return a.entry.isCommon ? -1 : 1;
      }
      final aPrimary = _isPrimary(a);
      final bPrimary = _isPrimary(b);
      if (aPrimary != bPrimary) {
        return aPrimary ? -1 : 1;
      }
      if (a.reasons.length != b.reasons.length) {
        return a.reasons.length - b.reasons.length;
      }
      return a.entry.id - b.entry.id;
    });
    return matches;
  }

  /// True when the matched base is the entry's own headword or reading.
  static bool _isPrimary(LookupResult r) =>
      r.entry.headword == r.baseForm ||
      toHiragana(r.entry.reading) == toHiragana(r.baseForm);

  LookupResult _result(
    String surface,
    int start,
    String base,
    String matchedReading,
    List<String> reasons,
    DictionaryEntry entry,
  ) => LookupResult(
    start: start,
    length: surface.length,
    surface: surface,
    baseForm: base,
    matchedReading: matchedReading,
    reasons: reasons,
    entry: entry,
  );

  /// `(entry id, reading of the matched form)` for every form row with the
  /// key [form] in build order (kanji forms before kana); an entry can appear
  /// twice, the caller keeps the first.
  List<(int, String)> _formMatches(String form) => [
    for (final row in _formsByKey.select([form]))
      (row['entry_id'] as int, row['reading'] as String),
  ];

  DictionaryEntry? _entry(int id, Map<int, DictionaryEntry?> cache) =>
      cache.putIfAbsent(id, () => _loadEntry(id));

  DictionaryEntry? _loadEntry(int id) {
    final rows = _entryById.select([id]);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final senses = [
      for (final s in _sensesByEntry.select([id]))
        Sense(
          glosses: _split(s['glosses'] as String),
          partsOfSpeech: (s['pos'] as String).split(' '),
        ),
    ];
    return DictionaryEntry(
      id: id,
      headword: row['headword'] as String,
      reading: row['reading'] as String,
      senses: senses,
      isCommon: row['is_common'] == 1,
    );
  }

  static Iterable<String> _pos(DictionaryEntry entry) =>
      entry.senses.expand((s) => s.partsOfSpeech);

  static List<String> _split(String joined) =>
      joined.isEmpty ? const [] : joined.split(DictBuilder.listSeparator);

  /// [index] moved back by one when it points at the low half of a
  /// surrogate pair, so a surface never starts inside a code point.
  static int _clampToBoundary(String text, int index) {
    if (index > 0 &&
        index < text.length &&
        _isLowSurrogate(text.codeUnitAt(index)) &&
        _isHighSurrogate(text.codeUnitAt(index - 1))) {
      return index - 1;
    }
    return index;
  }

  /// Candidate end offsets after [start], ascending, each on a code point
  /// boundary, at most [maxSurfaceUnits] units long and never past a break
  /// character.
  static List<int> _surfaceEnds(String text, int start) {
    final ends = <int>[];
    var pos = start;
    while (pos < text.length && pos - start < maxSurfaceUnits) {
      final unit = text.codeUnitAt(pos);
      if (lookupBreaks.contains(unit)) {
        break;
      }
      final pair =
          _isHighSurrogate(unit) &&
          pos + 1 < text.length &&
          _isLowSurrogate(text.codeUnitAt(pos + 1));
      pos += pair ? 2 : 1;
      if (pos - start > maxSurfaceUnits) {
        break;
      }
      ends.add(pos);
    }
    return ends;
  }

  static bool _isHighSurrogate(int unit) => unit & 0xFC00 == 0xD800;

  static bool _isLowSurrogate(int unit) => unit & 0xFC00 == 0xDC00;

  @override
  Future<KanjiEntry?> kanji(String literal) async {
    final rows = _kanjiByLiteral.select([literal]);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return KanjiEntry(
      literal: literal,
      meanings: _split(row['meanings'] as String),
      onReadings: _split(row['on_readings'] as String),
      kunReadings: _split(row['kun_readings'] as String),
      strokeCount: row['strokes'] as int?,
      grade: row['grade'] as int?,
      jlpt: row['jlpt'] as int?,
    );
  }
}
