import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/dictionary/deinflector.dart';

void main() {
  const deinflector = Deinflector();

  /// The candidate for [base] among the deinflections of [surface], or null.
  /// Several candidates can share a base (e.g. 食べられる is both potential
  /// and passive); the first one in rule order is the one a lookup shows.
  Deinflection? find(String surface, String base, {List<String>? reasons}) {
    for (final d in deinflector.deinflect(surface)) {
      if (d.base == base &&
          (reasons == null || d.reasons.join(' ') == reasons.join(' '))) {
        return d;
      }
    }
    return null;
  }

  void expectChain(
    String surface,
    String base,
    List<String> reasons,
    String pos,
  ) {
    final d = find(surface, base, reasons: reasons);
    expect(
      d,
      isNotNull,
      reason:
          '$surface should deinflect to $base via $reasons, got '
          '${deinflector.deinflect(surface).where((d) => d.base == base).map((d) => d.reasons).toList()}',
    );
    expect(
      d!.acceptsPos([pos]),
      isTrue,
      reason: '$surface -> $base must accept $pos',
    );
  }

  group('the first tests from PLAN.md WP3', () {
    test('食べられなかった -> 食べる [potential, negative, past]', () {
      expectChain('食べられなかった', '食べる', ['potential', 'negative', 'past'], 'v1');
    });

    test('行って -> 行く [te] (iku exception)', () {
      expectChain('行って', '行く', ['te'], 'v5k-s');
      expectChain('いって', 'いく', ['te'], 'v5k-s');
    });

    test('強そう -> 強い [sou]', () {
      expectChain('強そう', '強い', ['sou'], 'adj-i');
    });

    test('知っています -> 知る [te, progressive, polite]', () {
      expectChain('知っています', '知る', ['te', 'progressive', 'polite'], 'v5r');
    });

    test('読んでいた -> 読む [te, progressive, past]', () {
      expectChain('読んでいた', '読む', ['te', 'progressive', 'past'], 'v5m');
    });

    test('書かされた -> 書く [causative-passive, past]', () {
      expectChain('書かされた', '書く', ['causative-passive', 'past'], 'v5k');
    });

    test('大きくなかった -> 大きい [negative, past]', () {
      expectChain('大きくなかった', '大きい', ['negative', 'past'], 'adj-i');
    });
  });

  group('identity', () {
    test(
      'a dictionary form is its own candidate with no reasons and any POS',
      () {
        final d = find('食べる', '食べる', reasons: []);
        expect(d, isNotNull);
        expect(d!.acceptsPos(['n']), isTrue);
        expect(d.acceptsPos(['v1']), isTrue);
      },
    );
  });

  group('polite forms', () {
    test('ます family on ichidan, godan, suru and kuru', () {
      expectChain('食べます', '食べる', ['polite'], 'v1');
      expectChain('食べません', '食べる', ['negative', 'polite'], 'v1');
      expectChain('食べました', '食べる', ['past', 'polite'], 'v1');
      expectChain('食べませんでした', '食べる', ['negative', 'past', 'polite'], 'v1');
      expectChain('書きます', '書く', ['polite'], 'v5k');
      expectChain('行きます', '行く', ['polite'], 'v5k-s');
      expectChain('します', 'する', ['polite'], 'vs-i');
      expectChain('来ます', '来る', ['polite'], 'vk');
      expectChain('きます', 'くる', ['polite'], 'vk');
    });
  });

  group('te and past with the godan sound changes', () {
    test('te forms', () {
      expectChain('食べて', '食べる', ['te'], 'v1');
      expectChain('書いて', '書く', ['te'], 'v5k');
      expectChain('泳いで', '泳ぐ', ['te'], 'v5g');
      expectChain('話して', '話す', ['te'], 'v5s');
      expectChain('待って', '待つ', ['te'], 'v5t');
      expectChain('死んで', '死ぬ', ['te'], 'v5n');
      expectChain('読んで', '読む', ['te'], 'v5m');
      expectChain('買って', '買う', ['te'], 'v5u');
      expectChain('知って', '知る', ['te'], 'v5r');
      expectChain('遊んで', '遊ぶ', ['te'], 'v5b');
      expectChain('来て', '来る', ['te'], 'vk');
      expectChain('して', 'する', ['te'], 'vs-i');
      expectChain('強くて', '強い', ['te'], 'adj-i');
    });

    test('past forms', () {
      expectChain('食べた', '食べる', ['past'], 'v1');
      expectChain('書いた', '書く', ['past'], 'v5k');
      expectChain('泳いだ', '泳ぐ', ['past'], 'v5g');
      expectChain('行った', '行く', ['past'], 'v5k-s');
      expectChain('強かった', '強い', ['past'], 'adj-i');
      expectChain('来た', '来る', ['past'], 'vk');
      expectChain('した', 'する', ['past'], 'vs-i');
    });

    test('書いて must not reach 行く: the iku rule only fires on 行って/いって', () {
      expect(find('書いて', '書く')!.acceptsPos(['v5k-s']), isTrue);
      final d = find('行って', '行く', reasons: ['te'])!;
      expect(d.acceptsPos(['v5k']), isFalse);
    });
  });

  group('negative, conditional, volitional, imperative', () {
    test('negative', () {
      expectChain('食べない', '食べる', ['negative'], 'v1');
      expectChain('書かない', '書く', ['negative'], 'v5k');
      expectChain('買わない', '買う', ['negative'], 'v5u');
      expectChain('来ない', '来る', ['negative'], 'vk');
      expectChain('しない', 'する', ['negative'], 'vs-i');
      expectChain('強くない', '強い', ['negative'], 'adj-i');
      expectChain('食べなかった', '食べる', ['negative', 'past'], 'v1');
      expectChain('食べなくて', '食べる', ['negative', 'te'], 'v1');
    });

    test('ba and tara conditionals', () {
      expectChain('食べれば', '食べる', ['ba'], 'v1');
      expectChain('書けば', '書く', ['ba'], 'v5k');
      expectChain('強ければ', '強い', ['ba'], 'adj-i');
      expectChain('来れば', '来る', ['ba'], 'vk');
      expectChain('すれば', 'する', ['ba'], 'vs-i');
      expectChain('食べなければ', '食べる', ['negative', 'ba'], 'v1');
      expectChain('食べたら', '食べる', ['tara'], 'v1');
      expectChain('読んだら', '読む', ['tara'], 'v5m');
      expectChain('強かったら', '強い', ['tara'], 'adj-i');
    });

    test('volitional and imperative', () {
      expectChain('食べよう', '食べる', ['volitional'], 'v1');
      expectChain('書こう', '書く', ['volitional'], 'v5k');
      expectChain('来よう', '来る', ['volitional'], 'vk');
      expectChain('しよう', 'する', ['volitional'], 'vs-i');
      expectChain('食べましょう', '食べる', ['volitional', 'polite'], 'v1');
      expectChain('食べろ', '食べる', ['imperative'], 'v1');
      expectChain('書け', '書く', ['imperative'], 'v5k');
      expectChain('来い', '来る', ['imperative'], 'vk');
      expectChain('しろ', 'する', ['imperative'], 'vs-i');
    });
  });

  group('potential, passive, causative', () {
    test('potential', () {
      expectChain('食べられる', '食べる', ['potential'], 'v1');
      expectChain('食べれる', '食べる', ['potential'], 'v1');
      expectChain('書ける', '書く', ['potential'], 'v5k');
      expectChain('来られる', '来る', ['potential'], 'vk');
      expectChain('できる', 'する', ['potential'], 'vs-i');
    });

    test('passive', () {
      expectChain('食べられる', '食べる', ['passive'], 'v1');
      expectChain('書かれる', '書く', ['passive'], 'v5k');
      expectChain('される', 'する', ['passive'], 'vs-i');
      expectChain('来られる', '来る', ['passive'], 'vk');
    });

    test('causative and causative-passive', () {
      expectChain('食べさせる', '食べる', ['causative'], 'v1');
      expectChain('書かせる', '書く', ['causative'], 'v5k');
      expectChain('来させる', '来る', ['causative'], 'vk');
      expectChain('させる', 'する', ['causative'], 'vs-i');
      expectChain('食べさせられる', '食べる', ['causative-passive'], 'v1');
      expectChain('書かせられる', '書く', ['causative-passive'], 'v5k');
      expectChain('書かされる', '書く', ['causative-passive'], 'v5k');
      expectChain('させられる', 'する', ['causative-passive'], 'vs-i');
    });
  });

  group('auxiliaries on the stem and on the te form', () {
    test('tai, sou, sugiru, sa', () {
      expectChain('食べたい', '食べる', ['tai'], 'v1');
      expectChain('食べたくない', '食べる', ['tai', 'negative'], 'v1');
      expectChain('書きたかった', '書く', ['tai', 'past'], 'v5k');
      expectChain('食べそう', '食べる', ['sou'], 'v1');
      expectChain('食べすぎる', '食べる', ['sugiru'], 'v1');
      expectChain('強すぎる', '強い', ['sugiru'], 'adj-i');
      expectChain('強さ', '強い', ['sa'], 'adj-i');
    });

    test('progressive, chau, shimau', () {
      expectChain('食べている', '食べる', ['te', 'progressive'], 'v1');
      expectChain('食べてる', '食べる', ['te', 'progressive'], 'v1');
      expectChain('読んでる', '読む', ['te', 'progressive'], 'v5m');
      expectChain('食べちゃう', '食べる', ['te', 'chau'], 'v1');
      expectChain('食べちゃった', '食べる', ['te', 'chau', 'past'], 'v1');
      expectChain('読んじゃった', '読む', ['te', 'chau', 'past'], 'v5m');
      expectChain('食べてしまった', '食べる', ['te', 'shimau', 'past'], 'v1');
    });

    test('a long chain stays within the depth bound', () {
      expectChain('食べさせられたくなかった', '食べる', [
        'causative-passive',
        'tai',
        'negative',
        'past',
      ], 'v1');
    });
  });

  group('negative cases', () {
    test('a bare masu stem is not a word: たべ does not reach 食べる', () {
      expect(find('たべ', 'たべる'), isNull);
      expect(find('食べ', '食べる'), isNull);
    });

    test(
      '本ない does not deinflect to 本, and its verb candidate rejects nouns',
      () {
        expect(find('本ない', '本'), isNull);
        for (final d in deinflector.deinflect('本ない')) {
          if (d.reasons.isNotEmpty) {
            expect(
              d.acceptsPos(['n']),
              isFalse,
              reason: '${d.base} ${d.reasons}',
            );
          }
        }
      },
    );

    test(
      'a deinflected candidate only accepts the classes its rules produced',
      () {
        final d = find('食べられなかった', '食べる')!;
        expect(d.acceptsPos(['v5r']), isFalse);
        expect(d.acceptsPos(['adj-i']), isFalse);
        expect(d.acceptsPos(['n', 'v1']), isTrue);
      },
    );

    test('katakana input is not special-cased here: the lookup normalises', () {
      expect(find('タベタ', 'たべる'), isNull);
    });
  });
}
