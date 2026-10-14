import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yomitanuki/data/services/dictionary/sqlite_dictionary.dart';
import 'package:yomitanuki/domain/models/lookup_result.dart';

import '../../../fixtures/dict/mini_dictionary.dart';

void main() {
  late Directory tmp;
  late SqliteDictionary dict;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('yomitanuki_sqlite_dict_');
    final path = '${tmp.path}/dictionary.sqlite';
    buildMiniDictionary(path);
    dict = SqliteDictionary.openFile(path);
  });

  tearDownAll(() {
    dict.close();
    tmp.deleteSync(recursive: true);
  });

  /// The first result at [index], which the UI shows as the match.
  Future<LookupResult> first(String text, int index) async {
    final results = await dict.lookupAt(text, index);
    expect(results, isNotEmpty, reason: 'no match for "$text" at $index');
    return results.first;
  }

  void expectMatch(
    LookupResult r, {
    required String surface,
    required String base,
    required List<String> reasons,
    required int entry,
  }) {
    expect(r.surface, surface);
    expect(r.baseForm, base);
    expect(r.reasons, reasons);
    expect(r.entry.id, entry);
    expect(r.length, surface.length);
  }

  group('the first tests from PLAN.md WP3, end to end', () {
    test('食べられなかった', () async {
      expectMatch(
        await first('食べられなかった', 0),
        surface: '食べられなかった',
        base: '食べる',
        reasons: ['potential', 'negative', 'past'],
        entry: 1358280,
      );
    });

    test('行って', () async {
      expectMatch(
        await first('行って', 0),
        surface: '行って',
        base: '行く',
        reasons: ['te'],
        entry: 1578850,
      );
    });

    test('強そう', () async {
      expectMatch(
        await first('強そう', 0),
        surface: '強そう',
        base: '強い',
        reasons: ['sou'],
        entry: 1236070,
      );
    });

    test('来るはず is two lookups: 来る at 0, はず at 2', () async {
      expectMatch(
        await first('来るはず', 0),
        surface: '来る',
        base: '来る',
        reasons: [],
        entry: 1547720,
      );
      final hazu = await first('来るはず', 2);
      expectMatch(hazu, surface: 'はず', base: 'はず', reasons: [], entry: 1476430);
      expect(hazu.start, 2);
    });

    test('知っています', () async {
      expectMatch(
        await first('知っています', 0),
        surface: '知っています',
        base: '知る',
        reasons: ['te', 'progressive', 'polite'],
        entry: 1420470,
      );
    });

    test('読んでいた', () async {
      expectMatch(
        await first('読んでいた', 0),
        surface: '読んでいた',
        base: '読む',
        reasons: ['te', 'progressive', 'past'],
        entry: 1456360,
      );
    });

    test('書かされた', () async {
      expectMatch(
        await first('書かされた', 0),
        surface: '書かされた',
        base: '書く',
        reasons: ['causative-passive', 'past'],
        entry: 1343950,
      );
    });

    test('大きくなかった', () async {
      expectMatch(
        await first('大きくなかった', 0),
        surface: '大きくなかった',
        base: '大きい',
        reasons: ['negative', 'past'],
        entry: 1588880,
      );
    });
  });

  group('review additions, end to end', () {
    test('食べずに, 知らん, 食べといて', () async {
      expectMatch(
        await first('食べずに', 0),
        surface: '食べずに',
        base: '食べる',
        reasons: ['negative'],
        entry: 1358280,
      );
      expectMatch(
        await first('知らん', 0),
        surface: '知らん',
        base: '知る',
        reasons: ['negative'],
        entry: 1420470,
      );
      expectMatch(
        await first('食べといて', 0),
        surface: '食べといて',
        base: '食べる',
        reasons: ['te', 'toku'],
        entry: 1358280,
      );
    });
  });

  group('matched reading (D6b.2)', () {
    test(
      'a kana headword form reads as itself, in the script it is written',
      () async {
        final beer = await first('ビール', 0);
        expect(beer.entry.id, 1104550);
        expect(beer.entry.reading, 'ばくしゅ');
        expect(beer.matchedReading, 'ビール');
        expect((await first('びーる', 0)).matchedReading, 'ビール');
        expect((await first('コーヒー', 0)).matchedReading, 'コーヒー');
        expect((await first('たべる', 0)).matchedReading, 'たべる');
      },
    );

    test('a kanji form reads as the kana that applies to it', () async {
      expect((await first('麦酒', 0)).matchedReading, 'ばくしゅ');
      final byId = {for (final r in await dict.lookupAt('人', 0)) r.entry.id: r};
      expect(byId[1580640]!.matchedReading, 'ひと');
      expect(byId[1366420]!.matchedReading, 'と');
    });

    test('an inflected surface carries the base form\'s reading', () async {
      expect((await first('食べた', 0)).matchedReading, 'たべる');
      expect((await first('食べられなかった', 0)).matchedReading, 'たべる');
    });
  });

  group('opening', () {
    test('a missing file, a non-database and a foreign schema are DictionaryOpenError', () {
      expect(
        () => SqliteDictionary.openFile('${tmp.path}/missing.sqlite'),
        throwsA(isA<DictionaryOpenError>()),
      );

      final garbage = File('${tmp.path}/garbage.sqlite')
        ..writeAsStringSync('not a database at all');
      expect(
        () => SqliteDictionary.openFile(garbage.path),
        throwsA(isA<DictionaryOpenError>()),
      );

      final empty = '${tmp.path}/empty.sqlite';
      sqlite3.open(empty).close();
      expect(
        () => SqliteDictionary.openFile(empty),
        throwsA(isA<DictionaryOpenError>()),
      );

      // A real build whose schema_version was bumped: every query prepares,
      // only the version check can reject it.
      final foreign = '${tmp.path}/foreign.sqlite';
      buildMiniDictionary(foreign);
      final db = sqlite3.open(foreign);
      db.execute("UPDATE meta SET value = '999' WHERE key = 'schema_version'");
      db.close();
      expect(
        () => SqliteDictionary.openFile(foreign),
        throwsA(
          isA<DictionaryOpenError>().having(
            (e) => e.message,
            'message',
            contains('999'),
          ),
        ),
      );
    });
  });

  group('POS consistency', () {
    test('たべ alone is not 食べる', () async {
      final results = await dict.lookupAt('たべ', 0);
      expect(results.where((r) => r.entry.id == 1358280), isEmpty);
    });

    test('本ない only matches 本 as the one-character noun', () async {
      final results = await dict.lookupAt('本ない', 0);
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r.surface, '本');
        expect(r.reasons, isEmpty);
      }
    });

    test('a Xする surface finds the vs noun X', () async {
      expectMatch(
        await first('冒険した', 0),
        surface: '冒険した',
        base: '冒険',
        reasons: ['past'],
        entry: 1519830,
      );
      expectMatch(
        await first('します', 0),
        surface: 'します',
        base: 'する',
        reasons: ['polite'],
        entry: 1157170,
      );
    });

    test(
      'an ambiguous られる is reported once per entry, potential first',
      () async {
        final results = await dict.lookupAt('食べられる', 0);
        final taberu = results.where((r) => r.entry.id == 1358280).toList();
        expect(taberu, hasLength(1));
        expect(taberu.single.reasons, ['potential']);
      },
    );
  });

  group('ordering', () {
    test('longest surface first, then common entries first', () async {
      final results = await dict.lookupAt('本当に', 0);
      expect(results.map((r) => r.surface).toList(), ['本当', '本', '本']);
      // Both 本 entries are common; 本 is the headword of ほん and only a
      // spelling of 元【もと】, so ほん comes first.
      expect(results[1].entry.reading, 'ほん');
      expect(results[2].entry.reading, 'もと');

      // 人【ひと】 is common, 人【と】 is not: common first.
      final hito = await dict.lookupAt('人', 0);
      expect(hito.map((r) => r.entry.reading).toList(), ['ひと', 'と']);
      expect(hito[0].entry.isCommon, isTrue);
      expect(hito[1].entry.isCommon, isFalse);
    });

    test(
      'a kana surface ranks the entry whose reading it is as primary',
      () async {
        // こられる: 来る (reading くる) is primary; a kanji-headword entry whose
        // reading differs is not, so 来る stays first even though its headword
        // is kanji.
        final results = await dict.lookupAt('こられる', 0);
        expect(results.first.entry.headword, '来る');
        expect(results.first.reasons, ['potential']);
      },
    );

    test('a surface stops at whitespace and punctuation', () async {
      expect((await first('食べる はず', 0)).surface, '食べる');
      expect((await first('食べる。はず', 0)).surface, '食べる');
      expect((await first('食べる…はず', 0)).surface, '食べる');
      expect((await first('食べる・はず', 0)).surface, '食べる');
      expect((await first('食べる（はず', 0)).surface, '食べる');
      expect((await first('食べる!はず', 0)).surface, '食べる');
      expect((await first('食べる,はず', 0)).surface, '食べる');
    });
  });

  group('kana and code units', () {
    test('katakana and hiragana are interchangeable in readings', () async {
      // ビール is a kana form of 麦酒 【ばくしゅ】 in JMdict.
      final beer = await first('びーる', 0);
      expect(beer.entry.id, 1104550);
      expect(beer.surface, 'びーる');
      expect((await first('コーヒー', 0)).entry.headword, 'コーヒー');
      final r = await first('タベル', 0);
      expect(r.entry.id, 1358280);
      expect(r.surface, 'タベル');
    });

    test(
      'surrogate pairs are never split and the start is on a boundary',
      () async {
        const text = '𠮟り飛ばす';
        final r = await first(text, 0);
        expect(r.entry.id, 1319560);
        expect(r.length, text.length);
        expect(r.length, 6);
        // An index on the low surrogate is clamped to the pair's start.
        final clamped = await first(text, 1);
        expect(clamped.start, 0);
        expect(clamped.entry.id, 1319560);
      },
    );

    test('surfaces are capped at maxSurfaceUnits code units', () async {
      final text = '食べる${'あ' * 40}';
      expect(SqliteDictionary.maxSurfaceUnits, 24);
      expect((await first(text, 0)).surface, '食べる');
      expect(await dict.lookupAt('あ' * 40, 0), isEmpty);
      // A 25-unit form is in the fixture (entry 2108440) but can never be
      // matched: the longest surface tried is 24 units.
      const proverb = 'あやまちてはすなわちあらたむるにはばかることなかれ';
      expect(proverb.length, 25);
      final results = await dict.lookupAt('$proverbあああああ', 0);
      expect(results.where((r) => r.entry.id == 2108440), isEmpty);
      expect(results.map((r) => r.length), everyElement(lessThanOrEqualTo(24)));
    });

    test('an empty text or an index at the end yields nothing', () async {
      expect(await dict.lookupAt('', 0), isEmpty);
      expect(await dict.lookupAt('あ', 1), isEmpty);
    });

    test('an index outside the text is clamped', () async {
      final r = await first('食べる', -1);
      expect(r.start, 0);
      expect(r.entry.id, 1358280);
      expect(await dict.lookupAt('食べる', 99), isEmpty);
    });
  });

  group('entries', () {
    test('senses carry glosses and POS tags, and the common flag', () async {
      final entry = (await first('食べる', 0)).entry;
      expect(entry.headword, '食べる');
      expect(entry.reading, 'たべる');
      expect(entry.isCommon, isTrue);
      expect(entry.senses, hasLength(2));
      expect(entry.senses.first.glosses, ['to eat']);
      expect(entry.senses.first.partsOfSpeech, ['v1', 'vt']);
      expect(entry.senses[1].glosses, [
        'to live on (e.g. a salary)',
        'to live off',
        'to subsist on',
      ]);
    });

    test('kanji lookups come from KANJIDIC2', () async {
      final k = (await dict.kanji('食'))!;
      expect(k.literal, '食');
      expect(k.meanings, ['eat', 'food']);
      expect(k.onReadings, ['ショク', 'ジキ']);
      expect(k.kunReadings, ['く.う', 'く.らう', 'た.べる', 'は.む']);
      expect(k.strokeCount, 9);
      expect(k.grade, 2);
      expect(k.jlpt, 4);
      expect(await dict.kanji('あ'), isNull);
    });

    test('meta exposes the source versions for the about screen', () {
      expect(dict.meta['jmdict_version'], '3.6.2');
      expect(dict.meta['licence'], contains('EDRDG'));
    });
  });
}
