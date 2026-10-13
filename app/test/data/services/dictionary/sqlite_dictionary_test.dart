import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      // 本 (ほん, common) before 本 (もと, not common).
      expect(results[1].entry.reading, 'ほん');
      expect(results[1].entry.isCommon, isTrue);
      expect(results[2].entry.reading, 'もと');
    });

    test('a surface stops at whitespace and Japanese punctuation', () async {
      expect((await first('食べる はず', 0)).surface, '食べる');
      expect((await first('食べる。はず', 0)).surface, '食べる');
    });
  });

  group('kana and code units', () {
    test('katakana and hiragana are interchangeable in readings', () async {
      expect((await first('びーる', 0)).entry.headword, 'ビール');
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
    });

    test('an empty text or an index at the end yields nothing', () async {
      expect(await dict.lookupAt('', 0), isEmpty);
      expect(await dict.lookupAt('あ', 1), isEmpty);
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
