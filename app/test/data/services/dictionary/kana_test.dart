import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/dictionary/kana.dart';

void main() {
  test('katakana syllables become hiragana, the rest is untouched', () {
    expect(toHiragana('タベル'), 'たべる');
    expect(toHiragana('コーヒー'), 'こーひー');
    expect(toHiragana('ヴ'), 'ゔ');
    expect(toHiragana('食べる'), '食べる');
    expect(toHiragana('一ヶ月'), '一ヶ月');
    expect(toHiragana('ヷ'), 'ヷ');
    expect(toHiragana(''), '');
  });

  test('half-width katakana is folded, including voicing marks', () {
    expect(toHiragana('ﾋﾞｰﾙ'), 'びーる');
    expect(toHiragana('ﾊﾟﾝ'), 'ぱん');
    expect(toHiragana('ｳﾞｧｲｵﾘﾝ'), 'ゔぁいおりん');
    expect(toHiragana('ﾂﾞ'), 'づ');
    expect(toHiragana('ﾃﾞｰﾀ'), 'でーた');
    expect(toHiragana('ﾄﾞｱ'), 'どあ');
    expect(toHiragana('ｯﾁ'), 'っち');
    expect(toHiragana('ｦ'), 'を');
    expect(toHiragana('ﾝ'), 'ん');
    // A stray mark after a syllable that cannot take it is kept.
    expect(toHiragana('ｱﾞ'), 'あﾞ');
  });
}
