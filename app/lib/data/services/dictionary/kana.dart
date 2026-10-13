/// Katakana to hiragana, for the lookup keys of the `forms` table and for
/// the surface a lookup queries with. Half-width katakana (ｱ..ﾝ with ﾞ/ﾟ)
/// is folded to full width first. Only the syllables ァ..ヴ
/// (U+30A1..U+30F4) are then mapped; ヵ, ヶ, ヷ..ヺ and the long-vowel mark
/// ー stay as written, so 一ヶ月 is one key, not two.
String toHiragana(String text) {
  const first = 0x30A1;
  const last = 0x30F4;
  const offset = 0x60;
  StringBuffer? out;
  for (var i = 0; i < text.length; i++) {
    var unit = text.codeUnitAt(i);
    if (unit >= _halfWidthFirst && unit <= _halfWidthLast) {
      out ??= StringBuffer(text.substring(0, i));
      unit = _fullWidth.codeUnitAt(unit - _halfWidthFirst);
      if (i + 1 < text.length) {
        final voiced = _voice(unit, text.codeUnitAt(i + 1));
        if (voiced != null) {
          unit = voiced;
          i++;
        }
      }
    }
    if (unit >= first && unit <= last) {
      out ??= StringBuffer(text.substring(0, i));
      out.writeCharCode(unit - offset);
    } else {
      out?.writeCharCode(unit);
    }
  }
  return out?.toString() ?? text;
}

const int _halfWidthFirst = 0xFF66; // ｦ
const int _halfWidthLast = 0xFF9D; // ﾝ
const int _dakuten = 0xFF9E; // ﾞ
const int _handakuten = 0xFF9F; // ﾟ

/// Full-width katakana for U+FF66..U+FF9D, in code point order.
const String _fullWidth =
    'ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン';

/// The voiced form of [unit] when [mark] is a half-width ﾞ or ﾟ that applies
/// to it: カ..ト and ハ..ホ take ﾞ (+1), ハ..ホ take ﾟ (+2), ウ+ﾞ is ヴ.
int? _voice(int unit, int mark) {
  if (mark == _dakuten) {
    if (unit == 0x30A6) {
      return 0x30F4; // ウ → ヴ
    }
    // カ..チ alternate plain/voiced; ッ at U+30C3 breaks the pairing, so
    // ツ, テ and ト are listed; ハ..ホ come in plain/ﾞ/ﾟ triples.
    if ((unit >= 0x30AB && unit <= 0x30C1 && (unit - 0x30AB).isEven) ||
        unit == 0x30C4 ||
        unit == 0x30C6 ||
        unit == 0x30C8 ||
        (unit >= 0x30CF && unit <= 0x30DB && (unit - 0x30CF) % 3 == 0)) {
      return unit + 1;
    }
  } else if (mark == _handakuten) {
    if (unit >= 0x30CF && unit <= 0x30DB && (unit - 0x30CF) % 3 == 0) {
      return unit + 2;
    }
  }
  return null;
}
