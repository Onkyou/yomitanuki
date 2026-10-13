/// Katakana to hiragana, for the lookup keys of the `forms` table and for
/// the surface a lookup queries with. Only the syllables ァ..ヴ
/// (U+30A1..U+30F4) are mapped; ヵ, ヶ, ヷ..ヺ and the long-vowel mark ー
/// stay as written, so 一ヶ月 is one key, not two.
String toHiragana(String text) {
  const first = 0x30A1;
  const last = 0x30F4;
  const offset = 0x60;
  StringBuffer? out;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= first && unit <= last) {
      out ??= StringBuffer(text.substring(0, i));
      out.writeCharCode(unit - offset);
    } else {
      out?.writeCharCode(unit);
    }
  }
  return out?.toString() ?? text;
}
