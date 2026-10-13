import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yomitanuki/data/services/dictionary/dict_builder.dart';

import '../../../fixtures/dict/mini_dictionary.dart';

void main() {
  late Directory tmp;
  late String outPath;
  late Database db;
  const sep = DictBuilder.listSeparator;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('yomitanuki_dict_builder_');
    outPath = '${tmp.path}/dictionary.sqlite';
    buildMiniDictionary(outPath, meta: {'jmdict_release': 'test-release'});
    db = sqlite3.open(outPath, mode: OpenMode.readOnly);
  });

  tearDownAll(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  int count(String table) =>
      db.select('SELECT count(*) AS n FROM $table').first['n'] as int;

  test('every fixture word becomes one entry with its JMdict ent_seq', () {
    final words =
        (jsonDecode(File(miniJmdictPath).readAsStringSync())
                as Map<String, Object?>)['words']
            as List<Object?>;
    expect(count('entries'), words.length);
    final row = db.select('SELECT * FROM entries WHERE id = 1358280').single;
    expect(row['headword'], '食べる');
    expect(row['reading'], 'たべる');
    expect(row['is_common'], 1);
  });

  test('the headword skips secondary spellings and honours usually-kana', () {
    String headword(int id) =>
        db.select('SELECT headword FROM entries WHERE id = ?', [
              id,
            ]).single['headword']
            as String;
    // コーヒー: 珈琲 is ateji and the first sense is tagged uk.
    expect(headword(1049180), 'コーヒー');
    // ビール is only a kana form of 麦酒 【ばくしゅ】; no uk tag, so kanji stays.
    expect(headword(1104550), '麦酒');
    // 行く: 往く is rK, so 行く is the headword.
    expect(headword(1578850), '行く');
  });

  test(
    'senses keep glosses joined by the list separator, POS tags by space',
    () {
      final rows = db.select(
        'SELECT glosses, pos FROM senses WHERE entry_id = 1358280 ORDER BY seq',
      );
      expect(rows.first['glosses'], 'to eat');
      expect(rows.first['pos'], 'v1 vt');
      expect(
        rows[1]['glosses'],
        [
          'to live on (e.g. a salary)',
          'to live off',
          'to subsist on',
        ].join(sep),
      );
    },
  );

  test('forms index every kanji and kana form, katakana also as hiragana', () {
    List<Map<String, Object?>> forms(String form) =>
        db.select('SELECT entry_id, kind FROM forms WHERE form = ?', [form]);

    expect(forms('食べる'), [
      {'entry_id': 1358280, 'kind': 'kanji'},
    ]);
    expect(forms('たべる'), [
      {'entry_id': 1358280, 'kind': 'kana'},
    ]);
    // 喰べる is a search-only kanji form (sK): still a lookup key.
    expect(forms('喰べる').single['entry_id'], 1358280);
    // Katakana entries are findable by their hiragana normalisation.
    expect(forms('コーヒー').single['kind'], 'kana');
    expect(forms('こーひー').single['entry_id'], forms('コーヒー').single['entry_id']);
    // A kanji form containing katakana is normalised as well.
    expect(forms('一ヶ月').single['kind'], 'kanji');
    expect(forms('一ゖ月'), isEmpty, reason: 'ヶ is not a syllable; it stays');
    // Astral-plane kanji survive the round trip.
    expect(forms('𠮟り飛ばす').single['entry_id'], 1319560);
  });

  test('the list separator is a control character no gloss contains', () {
    expect(sep, '\u001F');
    expect(
      db
          .select("SELECT count(*) AS n FROM senses WHERE glosses LIKE '%; %'")
          .first['n'],
      greaterThan(0),
      reason: 'the fixture has glosses with "; " inside, which is why "; " is not the joiner',
    );
  });

  test('the forms table is indexed on form', () {
    final plan = db
        .select(
          'EXPLAIN QUERY PLAN SELECT entry_id FROM forms WHERE form = ?',
          ['x'],
        )
        .map((r) => r['detail'] as String)
        .join('\n');
    expect(plan, contains('USING INDEX'));
  });

  test('kanji rows carry readings, meanings, strokes, grade and JLPT', () {
    final row = db.select("SELECT * FROM kanji WHERE literal = '食'").single;
    expect(row['meanings'], ['eat', 'food'].join(sep));
    expect(row['on_readings'], ['ショク', 'ジキ'].join(sep));
    expect(row['kun_readings'], ['く.う', 'く.らう', 'た.べる', 'は.む'].join(sep));
    expect(row['strokes'], 9);
    expect(row['grade'], 2);
    expect(row['jlpt'], 4);
    expect(count('kanji'), 30);
  });

  test('meta records the source versions, the licence and extra keys', () {
    final meta = {
      for (final r in db.select('SELECT key, value FROM meta'))
        r['key'] as String: r['value'] as String,
    };
    expect(meta['jmdict_version'], '3.6.2');
    expect(meta['jmdict_date'], '2026-10-12');
    expect(meta['kanjidic_version'], '3.6.2');
    expect(meta['kanjidic_date'], '2026-10-12');
    expect(meta['schema_version'], '${DictBuilder.schemaVersion}');
    expect(
      meta['licence'],
      contains('Electronic Dictionary Research and Development Group'),
    );
    expect(meta['licence'], contains('CC BY-SA 4.0'));
    expect(meta['jmdict_release'], 'test-release');
  });

  test(
    'the returned stats match the tables, and a rebuild replaces the file',
    () {
      final path = '${tmp.path}/rebuilt.sqlite';
      buildMiniDictionary(path);
      final stats = buildMiniDictionary(path);
      final rebuilt = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(stats.entries, count('entries'));
        expect(stats.kanji, 30);
        expect(stats.forms, count('forms'));
        expect(
          rebuilt.select('SELECT count(*) AS n FROM entries').first['n'],
          stats.entries,
        );
      } finally {
        rebuilt.close();
      }
    },
  );
}
