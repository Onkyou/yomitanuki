import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/line_gloss.dart';

void main() {
  // 魔王を倒した勇者, cut the way LineGlosser cuts it.
  const maou = GlossSpan(
    start: 0,
    length: 2,
    surface: '魔王',
    reading: 'まおう',
    gloss: 'Satan',
    baseForm: '魔王',
    ruby: [RubySegment('魔王', 'まおう')],
  );
  const wo = GlossSpan(
    start: 2,
    length: 1,
    surface: 'を',
    ruby: [RubySegment('を')],
  );
  const taoshita = GlossSpan(
    start: 3,
    length: 3,
    surface: '倒した',
    reading: 'たおす',
    gloss: 'to throw down',
    baseForm: '倒す',
    ruby: [RubySegment('倒', 'たお'), RubySegment('した')],
  );
  const yuusha = GlossSpan(
    start: 6,
    length: 2,
    surface: '勇者',
    reading: 'ゆうしゃ',
    gloss: 'hero',
    baseForm: '勇者',
    ruby: [RubySegment('勇者', 'ゆうしゃ')],
  );
  const gloss = LineGloss('魔王を倒した勇者', [maou, wo, taoshita, yuusha]);

  group('rubyHtml (D6d.4)', () {
    test('every segment with a reading is a <ruby>, the rest is text', () {
      expect(
        gloss.rubyHtml(),
        '<ruby>魔王<rt>まおう</rt></ruby>を'
        '<ruby>倒<rt>たお</rt></ruby>した'
        '<ruby>勇者<rt>ゆうしゃ</rt></ruby>',
      );
    });

    test('the excepted span is bold and has no reading', () {
      expect(
        gloss.rubyHtml(exceptStart: 0, exceptLength: 2),
        '<b>魔王</b>を'
        '<ruby>倒<rt>たお</rt></ruby>した'
        '<ruby>勇者<rt>ゆうしゃ</rt></ruby>',
      );
    });

    test('an inflected span is excepted as a whole, even when the range '
        'covers only part of it', () {
      expect(
        gloss.rubyHtml(exceptStart: 3, exceptLength: 1),
        '<ruby>魔王<rt>まおう</rt></ruby>を<b>倒した</b>'
        '<ruby>勇者<rt>ゆうしゃ</rt></ruby>',
      );
    });

    test('a range that touches no span changes nothing', () {
      expect(gloss.rubyHtml(exceptStart: 8, exceptLength: 3), gloss.rubyHtml());
      expect(gloss.rubyHtml(exceptStart: 2, exceptLength: 0), gloss.rubyHtml());
      // A zero length inside a span is no target either: no bold, ruby kept.
      expect(gloss.rubyHtml(exceptStart: 1, exceptLength: 0), gloss.rubyHtml());
    });

    test('only the part of a plain stretch inside the range is bold', () {
      const plain = LineGloss('ええと、ね', [
        GlossSpan(
          start: 0,
          length: 5,
          surface: 'ええと、ね',
          ruby: [RubySegment('ええと、ね')],
        ),
      ]);

      expect(plain.rubyHtml(exceptStart: 1, exceptLength: 2), 'え<b>えと</b>、ね');
    });

    test('text and readings are escaped before markup is added', () {
      const odd = LineGloss('魔<王>&\n本', [
        GlossSpan(
          start: 0,
          length: 3,
          surface: '魔<王',
          reading: 'x',
          gloss: 'y',
          baseForm: '魔<王',
          ruby: [RubySegment('魔', 'ま<'), RubySegment('<王')],
        ),
        GlossSpan(
          start: 3,
          length: 4,
          surface: '>&\n本',
          ruby: [RubySegment('>&\n本')],
        ),
      ]);

      expect(odd.rubyHtml(), '<ruby>魔<rt>ま&lt;</rt></ruby>&lt;王&gt;&amp;<br>本');
      expect(
        odd.rubyHtml(exceptStart: 0, exceptLength: 1),
        '<b>魔&lt;王</b>&gt;&amp;<br>本',
      );
    });
  });
}
