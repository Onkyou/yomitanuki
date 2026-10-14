import '../models/line_gloss.dart';
import '../text/kana.dart';

/// Cuts [surface] into segments and puts the part of [reading] that belongs
/// to each run of kanji over it (furigana). JMdict has no per-kanji readings,
/// so the split is recovered: [form] (the dictionary spelling the surface
/// comes from, equal to [surface] unless it is inflected) becomes a pattern
/// in which every kanji run is a lazy group and every kana is itself, and
/// that pattern is matched against [reading]. 食べる / たべる gives
/// `(.+?)べる`, whose group is た.
///
/// An inflected [surface] (食べた for 食べる) is aligned on the prefix it shares
/// with [form], cut back to whole kanji runs; the rest, the inflection, is
/// left bare. When the reading does not fit the form, or nothing is shared,
/// the whole surface carries the whole reading if it has any kanji, else no
/// ruby.
///
/// Pure; segments are in order and adjacent bare text is one segment.
List<RubySegment> furigana(String surface, String form, String reading) {
  final kana = toHiragana(reading);
  final formRunes = form.runes.toList();
  final aligned = _align(formRunes, kana);
  final prefix = _sharedPrefixRunes(surface.runes.toList(), formRunes);
  if (aligned != null && prefix > 0) {
    final cut = _wholeRunsOnly(aligned, prefix);
    if (cut > 0) {
      final segments = <RubySegment>[];
      for (final part in _kuruReading(aligned, formRunes, surface, cut)) {
        if (part.start >= cut) break;
        final keep = cut - part.start;
        segments.add(
          keep >= part.length
              ? RubySegment(part.text, part.ruby)
              : RubySegment(String.fromCharCodes(part.text.runes.take(keep))),
        );
      }
      final tail = String.fromCharCodes(surface.runes.skip(cut));
      if (tail.isNotEmpty) segments.add(RubySegment(tail));
      return _mergeBare(segments);
    }
  }
  return [RubySegment(surface, formRunes.any(_isKanji) ? kana : null)];
}

/// A run of [form] with its reading, `start` in runes.
class _Part {
  const _Part(this.start, this.text, this.ruby);

  final int start;
  final String text;
  final String? ruby;

  int get length => text.runes.length;
}

/// [form] as kanji runs with their share of [kana] and kana runs without,
/// or null when [kana] does not fit the pattern.
List<_Part>? _align(List<int> form, String kana) {
  final runs = <(int, String, bool)>[]; // (start, text, isKanji)
  var i = 0;
  while (i < form.length) {
    final kanji = _isKanji(form[i]);
    final from = i;
    while (i < form.length && _isKanji(form[i]) == kanji) {
      i++;
    }
    runs.add((from, String.fromCharCodes(form.sublist(from, i)), kanji));
  }
  final pattern = StringBuffer('^');
  for (final (_, text, kanji) in runs) {
    pattern.write(kanji ? '(.+?)' : RegExp.escape(toHiragana(text)));
  }
  pattern.write(r'$');
  final match = RegExp(pattern.toString()).firstMatch(kana);
  if (match == null) {
    return null;
  }
  var group = 1;
  return [
    for (final (start, text, kanji) in runs)
      _Part(start, text, kanji ? match.group(group++) : null),
  ];
}

int _sharedPrefixRunes(List<int> a, List<int> b) {
  var n = 0;
  while (n < a.length && n < b.length && a[n] == b[n]) {
    n++;
  }
  return n;
}

/// 来る is read く, き or こ depending on what follows the 来 (来る, 来た, 来ない),
/// but JMdict only knows the dictionary reading. When [form] ends in 来る and
/// the alignment gave 来 the reading く, the reading is chosen from the first
/// character of the [surface] after 来. Only a 来 inside the aligned [cut]
/// is touched.
List<_Part> _kuruReading(
  List<_Part> parts,
  List<int> form,
  String surface,
  int cut,
) {
  final at = form.length - 2;
  if (at < 0 || form[at] != 0x6765 || form[at + 1] != 0x308B || cut <= at) {
    return parts;
  }
  final tail = String.fromCharCodes(surface.runes.skip(at + 1));
  final reading = switch (tail.isEmpty ? '' : tail[0]) {
    'な' || 'ら' || 'よ' || 'さ' || 'ず' || 'い' => 'こ',
    'た' || 'て' || 'ま' || 'ち' => 'き',
    _ => 'く',
  };
  return [
    for (final part in parts)
      part.start == at && part.ruby == 'く'
          ? _Part(part.start, part.text, reading)
          : part,
  ];
}

/// [prefix] (in runes) moved back to the start of the run it ends inside,
/// so no kanji run is claimed by half.
int _wholeRunsOnly(List<_Part> parts, int prefix) {
  for (final part in parts) {
    if (part.start + part.length > prefix) {
      return part.ruby == null ? prefix : part.start;
    }
  }
  return prefix;
}

List<RubySegment> _mergeBare(List<RubySegment> segments) {
  final out = <RubySegment>[];
  for (final s in segments) {
    if (s.ruby == null && out.isNotEmpty && out.last.ruby == null) {
      out[out.length - 1] = RubySegment(out.last.text + s.text);
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Han ideographs (BMP, Extension A, B..F, compatibility) and the marks
/// 々, 〆, ヵ and ヶ, which JMdict treats as part of a kanji run (一ヶ月).
bool _isKanji(int rune) =>
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0x20000 && rune <= 0x2FA1F) ||
    rune == 0x3005 ||
    rune == 0x3006 ||
    rune == 0x30F5 ||
    rune == 0x30F6;
