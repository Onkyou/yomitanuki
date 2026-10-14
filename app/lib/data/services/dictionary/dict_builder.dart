import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'kana.dart';

/// Row counts of a finished build, for the build log and the tests.
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

  @override
  String toString() =>
      'entries=$entries senses=$senses forms=$forms kanji=$kanji';
}

/// Turns decoded jmdict-simplified JSON (JMdict English + KANJIDIC2) into
/// the SQLite file `SqliteDictionary` reads. Used by `tool/dict/build_dict.dart`
/// for the real asset and by the tests for the committed mini fixture, so
/// the same code path is under test (.claude/wp3/NOTES.md D3.1).
///
/// Schema (schemaVersion 2):
///
/// - `entries(id, headword, reading, is_common)`: one row per JMdict entry;
///   `headword` is the first kanji form that is not a secondary spelling
///   (search-only, rare, outdated, irregular), else the kana reading (so
///   いらっしゃる, whose only kanji 居らっしゃる is search-only, shows as kana),
///   else the first kanji; an entry whose first sense is usually kana (`uk`)
///   leads with the reading.
/// - `senses(entry_id, seq, glosses, pos)`: glosses joined by
///   [listSeparator] (867 JMdict glosses contain `; ` themselves), POS tags
///   joined by a space.
/// - `forms(form, entry_id, kind, reading)`: every kanji and kana form, stored
///   with katakana normalised to hiragana (and as written when that differs),
///   indexed on `form`. `kind` is `kanji` or `kana`. `reading` is how that
///   form is read, identical under both keys of a form: a kana form's own
///   text as written (ビール), a kanji form's primary kana that applies to it
///   (麦酒 → ばくしゅ). Schema 1 had no `reading` column (D6b.2).
/// - `kanji(literal, meanings, on_readings, kun_readings, strokes, grade,
///   jlpt)`: KANJIDIC2, lists joined by [listSeparator].
/// - `meta(key, value)`: source versions and dates, schema version, licence.
class DictBuilder {
  static const int schemaVersion = 2;

  /// Joins the lists stored in one column (glosses, meanings, readings):
  /// ASCII unit separator, which no dictionary text contains ([_joined]
  /// refuses a build where one does).
  static const String listSeparator = '\u001F';

  /// [items] joined by [listSeparator]; throws [FormatException] when an
  /// item contains the separator, so an upstream release that ever used it
  /// fails the build instead of corrupting a column.
  static String _joined(Iterable<String> items, String what) {
    final list = items.toList();
    for (final item in list) {
      if (item.contains(listSeparator)) {
        throw FormatException('$what contains U+001F: "$item"');
      }
    }
    return list.join(listSeparator);
  }

  /// The EDRDG attribution the app's about screen shows (PLAN.md §1).
  static const String licence =
      'This app uses the JMdict and KANJIDIC2 dictionary files. These files '
      'are the property of the Electronic Dictionary Research and '
      'Development Group (EDRDG), and are used in conformance with the '
      "Group's licence (Creative Commons Attribution-ShareAlike 4.0, "
      'CC BY-SA 4.0): https://www.edrdg.org/edrdg/licence.html';

  /// Builds [outPath] from scratch; an existing file is replaced. Extra
  /// [meta] keys (release tags, checksums) are stored next to the built-in
  /// ones.
  static DictionaryBuildStats build({
    required Map<String, Object?> jmdict,
    required Map<String, Object?> kanjidic,
    required String outPath,
    Map<String, String> meta = const {},
  }) {
    // Built as <outPath>.part and renamed at the end, so an interrupted
    // build never leaves a file a `make` rule would consider up to date.
    final out = File(outPath);
    final part = File('$outPath.part');
    if (part.existsSync()) {
      part.deleteSync();
    }
    final db = sqlite3.open(part.path);
    final DictionaryBuildStats stats;
    try {
      db.execute('PRAGMA journal_mode = OFF');
      db.execute('PRAGMA synchronous = OFF');
      _createSchema(db);
      db.execute('BEGIN');
      final words = _writeWords(db, _list(jmdict['words']));
      final kanji = _writeKanji(db, _list(kanjidic['characters']));
      _writeMeta(db, {
        'schema_version': '$schemaVersion',
        'jmdict_version': _string(jmdict['version']),
        'jmdict_date': _string(jmdict['dictDate']),
        'kanjidic_version': _string(kanjidic['version']),
        'kanjidic_date': _string(kanjidic['dictDate']),
        'licence': licence,
        ...meta,
      });
      db.execute('COMMIT');
      db.execute('CREATE INDEX forms_form ON forms(form)');
      db.execute('ANALYZE');
      stats = DictionaryBuildStats(
        entries: words.entries,
        senses: words.senses,
        forms: words.forms,
        kanji: kanji,
      );
    } finally {
      db.close();
    }
    if (out.existsSync()) {
      out.deleteSync();
    }
    part.renameSync(outPath);
    return stats;
  }

  static void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
      CREATE TABLE entries(
        id INTEGER PRIMARY KEY,
        headword TEXT NOT NULL,
        reading TEXT NOT NULL,
        is_common INTEGER NOT NULL
      );
      CREATE TABLE senses(
        entry_id INTEGER NOT NULL,
        seq INTEGER NOT NULL,
        glosses TEXT NOT NULL,
        pos TEXT NOT NULL,
        PRIMARY KEY(entry_id, seq)
      ) WITHOUT ROWID;
      CREATE TABLE forms(
        form TEXT NOT NULL,
        entry_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        reading TEXT NOT NULL
      );
      CREATE TABLE kanji(
        literal TEXT PRIMARY KEY,
        meanings TEXT NOT NULL,
        on_readings TEXT NOT NULL,
        kun_readings TEXT NOT NULL,
        strokes INTEGER,
        grade INTEGER,
        jlpt INTEGER
      ) WITHOUT ROWID;
    ''');
  }

  static ({int entries, int senses, int forms}) _writeWords(
    Database db,
    List<Object?> words,
  ) {
    final insertEntry = db.prepare(
      'INSERT INTO entries(id, headword, reading, is_common) VALUES (?, ?, ?, ?)',
    );
    final insertSense = db.prepare(
      'INSERT INTO senses(entry_id, seq, glosses, pos) VALUES (?, ?, ?, ?)',
    );
    final insertForm = db.prepare(
      'INSERT INTO forms(form, entry_id, kind, reading) VALUES (?, ?, ?, ?)',
    );
    var entries = 0;
    var senseCount = 0;
    var forms = 0;
    try {
      for (final raw in words) {
        final word = _map(raw);
        final id = int.parse(_string(word['id']));
        final kanji = _list(word['kanji']).map(_map).toList();
        final kana = _list(word['kana']).map(_map).toList();
        final headKanji = _primary(kanji);
        final reading =
            _primary(kana, appliesTo: headKanji) ??
            _first(kana, appliesTo: headKanji);
        final senses = _list(word['sense']).map(_map).toList();
        final usuallyKana =
            senses.isNotEmpty &&
            _list(senses.first['misc']).map(_string).contains('uk');
        // Non-secondary kanji, else the kana reading, else (no kana at all)
        // the first kanji however it is tagged; usually-kana entries lead
        // with the reading.
        final headword = usuallyKana
            ? reading ?? headKanji ?? _first(kanji)
            : headKanji ?? reading ?? _first(kanji);
        if (headword == null) {
          continue;
        }
        final common = [...kanji, ...kana].any((f) => f['common'] == true);
        insertEntry.execute([id, headword, reading ?? '', common ? 1 : 0]);
        entries++;

        var seq = 0;
        for (final sense in senses) {
          final glosses = [
            for (final g in _list(sense['gloss'])) _string(_map(g)['text']),
          ];
          final pos = _list(sense['partOfSpeech']).map(_string).join(' ');
          insertSense.execute([
            id,
            seq++,
            _joined(glosses, 'gloss of $id'),
            pos,
          ]);
          senseCount++;
        }

        for (final (list, kind) in [(kanji, 'kanji'), (kana, 'kana')]) {
          for (final form in list) {
            final text = _string(form['text']);
            final formReading = kind == 'kana'
                ? text
                : _primary(kana, appliesTo: text) ??
                      _first(kana, appliesTo: text) ??
                      reading ??
                      '';
            for (final key in {toHiragana(text), text}) {
              insertForm.execute([key, id, kind, formReading]);
              forms++;
            }
          }
        }
      }
    } finally {
      insertEntry.close();
      insertSense.close();
      insertForm.close();
    }
    return (entries: entries, senses: senseCount, forms: forms);
  }

  /// Forms with these tags are lookup keys but never the headword:
  /// search-only (`sK`/`sk`), rarely used (`rK`/`rk`), outdated (`oK`/`ok`)
  /// and irregular (`iK`/`ik`) spellings.
  static const Set<String> _secondaryTags = {
    'sK',
    'sk',
    'rK',
    'rk',
    'oK',
    'ok',
    'iK',
    'ik',
  };

  /// The text of the first form that is not a secondary spelling and, for
  /// kana, applies to [appliesTo]; null when there is none.
  static String? _primary(
    List<Map<String, Object?>> forms, {
    String? appliesTo,
  }) {
    for (final form in forms) {
      if (_list(form['tags']).map(_string).any(_secondaryTags.contains)) {
        continue;
      }
      if (_applies(form, appliesTo)) {
        return _string(form['text']);
      }
    }
    return null;
  }

  /// The text of the first form of any kind that applies to [appliesTo],
  /// else the first form; null when there are no forms.
  static String? _first(List<Map<String, Object?>> forms, {String? appliesTo}) {
    for (final form in forms) {
      if (_applies(form, appliesTo)) {
        return _string(form['text']);
      }
    }
    return forms.isEmpty ? null : _string(forms.first['text']);
  }

  static bool _applies(Map<String, Object?> form, String? appliesTo) {
    if (appliesTo == null) {
      return true;
    }
    final applies = _list(form['appliesToKanji']).map(_string);
    return applies.contains('*') || applies.contains(appliesTo);
  }

  static int _writeKanji(Database db, List<Object?> characters) {
    final insert = db.prepare(
      'INSERT INTO kanji(literal, meanings, on_readings, kun_readings, '
      'strokes, grade, jlpt) VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    var count = 0;
    try {
      for (final raw in characters) {
        final character = _map(raw);
        final misc = _map(character['misc']);
        final strokes = _list(misc['strokeCounts']);
        final meanings = <String>[];
        final on = <String>[];
        final kun = <String>[];
        final readingMeaning = character['readingMeaning'];
        if (readingMeaning != null) {
          for (final raw in _list(_map(readingMeaning)['groups'])) {
            final group = _map(raw);
            for (final r in _list(group['readings']).map(_map)) {
              switch (_string(r['type'])) {
                case 'ja_on':
                  on.add(_string(r['value']));
                case 'ja_kun':
                  kun.add(_string(r['value']));
              }
            }
            for (final m in _list(group['meanings']).map(_map)) {
              if (_string(m['lang']) == 'en') {
                meanings.add(_string(m['value']));
              }
            }
          }
        }
        final literal = _string(character['literal']);
        insert.execute([
          literal,
          _joined(meanings, 'meaning of $literal'),
          _joined(on, 'reading of $literal'),
          _joined(kun, 'reading of $literal'),
          strokes.isEmpty ? null : strokes.first as int,
          misc['grade'] as int?,
          misc['jlptLevel'] as int?,
        ]);
        count++;
      }
    } finally {
      insert.close();
    }
    return count;
  }

  static void _writeMeta(Database db, Map<String, String> meta) {
    final insert = db.prepare('INSERT INTO meta(key, value) VALUES (?, ?)');
    try {
      for (final MapEntry(:key, :value) in meta.entries) {
        insert.execute([key, value]);
      }
    } finally {
      insert.close();
    }
  }

  static Map<String, Object?> _map(Object? value) =>
      value as Map<String, Object?>;

  static List<Object?> _list(Object? value) =>
      value == null ? const [] : value as List<Object?>;

  static String _string(Object? value) => value as String;
}
