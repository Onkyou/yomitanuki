import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';
import 'package:yomitanuki/domain/use_cases/furigana.dart';

void main() {
  group('furigana aligns the reading with the kanji runs of the form', () {
    test('食べる / たべる puts た over 食 and leaves okurigana bare', () {
      expect(furigana('食べる', '食べる', 'たべる'), const [
        RubySegment('食', 'た'),
        RubySegment('べる'),
      ]);
    });

    test('魔王 / まおう is one run: the whole reading over the whole word', () {
      expect(furigana('魔王', '魔王', 'まおう'), const [RubySegment('魔王', 'まおう')]);
    });

    test('お茶 / おちゃ leaves the leading kana bare', () {
      expect(furigana('お茶', 'お茶', 'おちゃ'), const [
        RubySegment('お'),
        RubySegment('茶', 'ちゃ'),
      ]);
    });

    test('大人 / おとな (irregular) is one run, so it still lines up', () {
      expect(furigana('大人', '大人', 'おとな'), const [RubySegment('大人', 'おとな')]);
    });

    test('two kanji runs around kana each get their share', () {
      expect(furigana('受け入れる', '受け入れる', 'うけいれる'), const [
        RubySegment('受', 'う'),
        RubySegment('け'),
        RubySegment('入', 'い'),
        RubySegment('れる'),
      ]);
    });

    test('a repeated-kanji mark belongs to its run: 人々 / ひとびと', () {
      expect(furigana('人々', '人々', 'ひとびと'), const [RubySegment('人々', 'ひとびと')]);
    });

    test('a katakana reading is compared and shown as hiragana', () {
      expect(furigana('食べる', '食べる', 'タベル'), const [
        RubySegment('食', 'た'),
        RubySegment('べる'),
      ]);
    });

    test('an astral-plane kanji is a kanji: 𠮟る / しかる', () {
      expect(furigana('𠮟る', '𠮟る', 'しかる'), const [
        RubySegment('𠮟', 'しか'),
        RubySegment('る'),
      ]);
    });

    test('ヶ inside a number-like run belongs to the run: 一ヶ月ぶり', () {
      expect(furigana('一ヶ月ぶり', '一ヶ月ぶり', 'いっかげつぶり'), const [
        RubySegment('一ヶ月', 'いっかげつ'),
        RubySegment('ぶり'),
      ]);
    });

    test('a kana form has no ruby at all', () {
      expect(furigana('ビール', 'ビール', 'ビール'), const [RubySegment('ビール')]);
    });
  });

  group(
    'an inflected surface is aligned on its prefix shared with the form',
    () {
      test('食べた vs 食べる: the inflection joins the bare kana', () {
        expect(furigana('食べた', '食べる', 'たべる'), const [
          RubySegment('食', 'た'),
          RubySegment('べた'),
        ]);
      });

      test('行って vs 行く: only the kanji gets ruby', () {
        expect(furigana('行って', '行く', 'いく'), const [
          RubySegment('行', 'い'),
          RubySegment('って'),
        ]);
      });

      test('a prefix that ends inside a kanji run does not claim that run', () {
        // 大 is shared with 大人, but the run 大人 is only half there.
        expect(furigana('大きい', '大人', 'おとな'), const [RubySegment('大きい', 'おとな')]);
      });
    },
  );

  group('来る changes its reading with what follows (く, こ, き)', () {
    test('来る keeps く', () {
      expect(furigana('来る', '来る', 'くる'), const [
        RubySegment('来', 'く'),
        RubySegment('る'),
      ]);
    });

    test('来た and 来て, 来ます, 来ちゃう read き', () {
      for (final surface in ['来た', '来て', '来ます', '来ちゃう']) {
        expect(furigana(surface, '来る', 'くる'), [
          const RubySegment('来', 'き'),
          RubySegment(surface.substring(1)),
        ], reason: surface);
      }
    });

    test('来ない, 来られ, 来い, 来させ, 来ず read こ', () {
      for (final surface in ['来ない', '来られ', '来い', '来させ', '来ず', '来よう']) {
        expect(furigana(surface, '来る', 'くる'), [
          const RubySegment('来', 'こ'),
          RubySegment(surface.substring(1)),
        ], reason: surface);
      }
    });

    test('any other tail keeps く', () {
      expect(furigana('来れば', '来る', 'くる'), const [
        RubySegment('来', 'く'),
        RubySegment('れば'),
      ]);
    });

    test('a compound ending in 来る follows the same rule', () {
      expect(furigana('持って来た', '持って来る', 'もってくる'), const [
        RubySegment('持', 'も'),
        RubySegment('って'),
        RubySegment('来', 'き'),
        RubySegment('た'),
      ]);
    });

    test('a different kanji before る is left alone', () {
      expect(furigana('見た', '見る', 'みる'), const [
        RubySegment('見', 'み'),
        RubySegment('た'),
      ]);
    });
  });

  group('when the reading does not fit the form', () {
    test('the whole surface carries the whole reading', () {
      expect(furigana('食べる', '食べる', 'のむ'), const [RubySegment('食べる', 'のむ')]);
    });

    test('a surface sharing no prefix with the form does too', () {
      expect(furigana('見た', '来る', 'くる'), const [RubySegment('見た', 'くる')]);
    });

    test('a kana-only surface gets no ruby even then', () {
      expect(furigana('だった', 'だ', 'のむ'), const [RubySegment('だった')]);
    });
  });
}
