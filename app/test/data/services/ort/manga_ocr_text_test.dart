import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/ort/manga_ocr_text.dart';

import '../../../support/goldens.dart';
import '../../../support/ort_test_env.dart';

void main() {
  group('postProcess (manga_ocr.ocr.post_process)', () {
    // Expected values produced by the reference implementation itself:
    // wp0/ocr_ort.py's post_process with jaconv 0.5.0 (the pinned venv), so
    // every row is parity with Python, not an opinion about the right answer.
    const cases = <String, String>{
      'こんにちは 世界': 'こんにちは世界',
      '　全角スペース　': '全角スペース',
      'a1!': 'ａ１！',
      '…': '．．．',
      '・・・': '．．．',
      '・': '・',
      '...': '．．．',
      '.': '．',
      '．．': '．．',
      'ｶﾞｷﾞ ｱｲｳ': 'ガギアイウ',
      'ｳﾞ': 'ヴ',
      'ﾞ': 'ﾞ',
      '｡｢｣､･': '。「」、・',
      'ヵヶ': 'ヵヶ',
      'ｰ': 'ー',
      '"\'`\\': '＂＇｀＼',
      '~': '～',
      'A\tB\nC': 'ＡＢＣ',
      ' x': 'ｘ',
      '​x': '​ｘ',
      '1.5': '１．５',
      '。。。': '。。。',
      '…。': '．．．。',
      '……': '．．．．．．',
      'ｱ・ｲ': 'ア・イ',
      'ﾊﾟﾋﾟ': 'パピ',
      // Whitespace goes first, so a split dakuten still merges.
      'ｶ ﾞ': 'ガ',
      '　・　・': '．．',
      'ABC xyz 123': 'ＡＢＣｘｙｚ１２３',
      // Python's str.split() whitespace, not Dart's \s: NEL and the C0
      // separators are whitespace, the BOM is not.
      '\x85x': 'ｘ',
      '\x1fx': 'ｘ',
      '﻿x': '﻿ｘ',
      '\x0bx\x0cy\rz': 'ｘｙｚ',
      'ｦﾝ': 'ヲン',
      'ｯｬ': 'ッャ',
      '10年後...また会おう': '１０年後．．．また会おう',
      '３日で終わる…': '３日で終わる．．．',
      '': '',
      '・.・': '．．．',
      'ﾊﾞﾊﾞﾊﾟ': 'ババパ',
      // A dakuten after a kana that has no voiced form stays half-width.
      'ｱﾞ': 'アﾞ',
      'ｶﾞ': 'ガ',
    };

    for (final MapEntry(key: input, value: expected) in cases.entries) {
      test('${_show(input)} -> ${_show(expected)}', () {
        expect(postProcess(input), expected);
      });
    }
  });

  group('MangaOcrVocab.detokenise', () {
    final vocab = MangaOcrVocab.parse(
      '[PAD]\n[UNK]\n[CLS]\n[SEP]\n[MASK]\n<unused0>\n<unused1>\nあ\nい\n',
    );

    test('skips the special ids 0-4 and <unusedN>, joins the rest', () {
      expect(vocab.detokenise([2, 2, 7, 0, 5, 8, 1, 4, 6, 3]), 'あい');
    });

    test('counts one token per line, without the trailing newline', () {
      expect(vocab.length, 9);
    });

    test('rejects an id outside the vocabulary', () {
      expect(() => vocab.detokenise([2, 9, 3]), throwsArgumentError);
      expect(() => vocab.detokenise([2, -1, 3]), throwsArgumentError);
    });
  });

  group('WP0b goldens', () {
    final vocab = MangaOcrVocab.parse(
      File('${modelDirectory().path}/vocab.txt').readAsStringSync(),
    );

    for (final golden in loadOcrGoldens(goldensDirectory())) {
      test('${golden.name}: text == postProcess(detokenise(ids))', () {
        expect(postProcess(vocab.detokenise(golden.ids)), golden.text);
      });
    }
  });
}

/// Test names with the invisible characters spelled out.
String _show(String s) => s.runes
    .map(
      (r) => r < 0x20 || const {0x85, 0xa0, 0x200b, 0x3000, 0xfeff}.contains(r)
          ? '\\u${r.toRadixString(16).padLeft(4, '0')}'
          : String.fromCharCode(r),
    )
    .join();
