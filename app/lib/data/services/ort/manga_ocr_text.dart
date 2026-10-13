/// manga-ocr's text side in Dart: the tokeniser's vocabulary and
/// `manga_ocr.ocr.post_process` (WP0 contract, `.claude/wp0/NOTES.md`
/// "What the Dart port has to reproduce"; reference `wp0/ocr_ort.py`).
///
/// Pure functions: no I/O, no logging. Parity with the Python reference is
/// what the tests assert, so each step below names the Python it mirrors.
library;

/// `vocab.txt`: one token per line, index == token id. The decoder's vocab
/// size (6144) equals the line count, so every argmax is a valid id.
class MangaOcrVocab {
  MangaOcrVocab._(this._tokens);

  /// Parses the file contents (`str.split("\n")` in Python; a trailing
  /// newline does not add a token, Python's empty last entry is never
  /// reached because logits have exactly one row per real token).
  factory MangaOcrVocab.parse(String vocabTxt) {
    final lines = vocabTxt.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return MangaOcrVocab._(List.unmodifiable(lines));
  }

  final List<String> _tokens;

  int get length => _tokens.length;

  /// `OrtMangaOcr.detokenise` without its post_process call: drops the
  /// special ids ([PAD] 0, [UNK] 1, [CLS] 2, [SEP] 3, [MASK] 4) and every
  /// `<unusedN>` token (C11), concatenates the rest (one character per token,
  /// no `##` pieces in this vocabulary).
  String detokenise(List<int> ids) {
    final out = StringBuffer();
    for (final id in ids) {
      if (id < 0 || id >= _tokens.length) {
        throw ArgumentError.value(
          id,
          'ids',
          'outside the vocabulary (0..${_tokens.length - 1})',
        );
      }
      if (id <= 4) continue;
      final token = _tokens[id];
      if (token.startsWith('<unused')) continue;
      out.write(token);
    }
    return out.toString();
  }
}

/// `manga_ocr.ocr.post_process`: strip all whitespace, `…` -> `...`, every
/// run of two or more `・`/`.` becomes the same number of `.`, then
/// `jaconv.h2z(text, ascii=True, digit=True)` with its default `kana=True`.
String postProcess(String text) {
  var t = _stripPythonWhitespace(text);
  t = t.replaceAll('…', '...');
  t = t.replaceAllMapped(RegExp('[・.]{2,}'), (m) => '.' * (m.end - m.start));
  return halfToFullWidth(t);
}

/// `"".join(text.split())`: Python's `str.split()` with no separator splits
/// on `str.isspace()` characters, which is not Dart's `\s` (NEL U+0085 and
/// the C0 separators U+001C..U+001F count, the BOM U+FEFF does not).
String _stripPythonWhitespace(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (!_isPythonSpace(rune)) out.writeCharCode(rune);
  }
  return out.toString();
}

bool _isPythonSpace(int r) =>
    (r >= 0x09 && r <= 0x0d) ||
    (r >= 0x1c && r <= 0x20) ||
    r == 0x85 ||
    r == 0xa0 ||
    r == 0x1680 ||
    (r >= 0x2000 && r <= 0x200a) ||
    r == 0x2028 ||
    r == 0x2029 ||
    r == 0x202f ||
    r == 0x205f ||
    r == 0x3000;

/// `jaconv.h2z(text, ignore='', kana=True, ascii=True, digit=True)`
/// (jaconv 0.5.0): half-width katakana with a following dakuten/handakuten
/// merge into one full-width character first, then a per-character table
/// maps the printable ASCII range to the full-width forms (U+FF01..U+FF5E,
/// space to U+3000) and the half-width katakana block to katakana.
String halfToFullWidth(String text) {
  var t = text;
  for (final MapEntry(key: half, value: full) in _dakuten.entries) {
    t = t.replaceAll(half, full);
  }
  final out = StringBuffer();
  for (final rune in t.runes) {
    if (rune == 0x20) {
      out.writeCharCode(0x3000);
    } else if (rune >= 0x21 && rune <= 0x7e) {
      out.writeCharCode(rune + 0xfee0);
    } else {
      out.writeCharCode(_halfKana[rune] ?? rune);
    }
  }
  return out.toString();
}

/// jaconv's `_conv_dakuten`, in its replacement order.
const Map<String, String> _dakuten = {
  'ｶﾞ': 'ガ', 'ｷﾞ': 'ギ', 'ｸﾞ': 'グ', 'ｹﾞ': 'ゲ', 'ｺﾞ': 'ゴ', //
  'ｻﾞ': 'ザ', 'ｼﾞ': 'ジ', 'ｽﾞ': 'ズ', 'ｾﾞ': 'ゼ', 'ｿﾞ': 'ゾ', //
  'ﾀﾞ': 'ダ', 'ﾁﾞ': 'ヂ', 'ﾂﾞ': 'ヅ', 'ﾃﾞ': 'デ', 'ﾄﾞ': 'ド', //
  'ﾊﾞ': 'バ', 'ﾋﾞ': 'ビ', 'ﾌﾞ': 'ブ', 'ﾍﾞ': 'ベ', 'ﾎﾞ': 'ボ', //
  'ﾊﾟ': 'パ', 'ﾋﾟ': 'ピ', 'ﾌﾟ': 'プ', 'ﾍﾟ': 'ペ', 'ﾎﾟ': 'ポ', //
  'ｳﾞ': 'ヴ',
};

/// jaconv's `H2Z_ALL` minus the ASCII range: U+FF61..U+FF9D (the half-width
/// katakana block without the lone dakuten marks U+FF9E/U+FF9F, which
/// jaconv leaves as they are). The table also maps seven full-width kana to
/// themselves, which the fallthrough above already does.
const Map<int, int> _halfKana = {
  0xff61: 0x3002, 0xff62: 0x300c, 0xff63: 0x300d, 0xff64: 0x3001, //
  0xff65: 0x30fb, 0xff66: 0x30f2, 0xff67: 0x30a1, 0xff68: 0x30a3, //
  0xff69: 0x30a5, 0xff6a: 0x30a7, 0xff6b: 0x30a9, 0xff6c: 0x30e3, //
  0xff6d: 0x30e5, 0xff6e: 0x30e7, 0xff6f: 0x30c3, 0xff70: 0x30fc, //
  0xff71: 0x30a2, 0xff72: 0x30a4, 0xff73: 0x30a6, 0xff74: 0x30a8, //
  0xff75: 0x30aa, 0xff76: 0x30ab, 0xff77: 0x30ad, 0xff78: 0x30af, //
  0xff79: 0x30b1, 0xff7a: 0x30b3, 0xff7b: 0x30b5, 0xff7c: 0x30b7, //
  0xff7d: 0x30b9, 0xff7e: 0x30bb, 0xff7f: 0x30bd, 0xff80: 0x30bf, //
  0xff81: 0x30c1, 0xff82: 0x30c4, 0xff83: 0x30c6, 0xff84: 0x30c8, //
  0xff85: 0x30ca, 0xff86: 0x30cb, 0xff87: 0x30cc, 0xff88: 0x30cd, //
  0xff89: 0x30ce, 0xff8a: 0x30cf, 0xff8b: 0x30d2, 0xff8c: 0x30d5, //
  0xff8d: 0x30d8, 0xff8e: 0x30db, 0xff8f: 0x30de, 0xff90: 0x30df, //
  0xff91: 0x30e0, 0xff92: 0x30e1, 0xff93: 0x30e2, 0xff94: 0x30e4, //
  0xff95: 0x30e6, 0xff96: 0x30e8, 0xff97: 0x30e9, 0xff98: 0x30ea, //
  0xff99: 0x30eb, 0xff9a: 0x30ec, 0xff9b: 0x30ed, 0xff9c: 0x30ef, //
  0xff9d: 0x30f3,
};
