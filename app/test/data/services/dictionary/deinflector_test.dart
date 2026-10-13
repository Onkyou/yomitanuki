import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/dictionary/deinflector.dart';

void main() {
  const deinflector = Deinflector();

  /// The candidates for [base] among the deinflections of [surface], with
  /// [reasons] when given. Several candidates can share a base and reasons
  /// (て→る produces 来る as an ichidan candidate next to the kuru rule's);
  /// the lookup's POS filter is what tells them apart.
  List<Deinflection> candidates(
    String surface,
    String base, [
    List<String>? reasons,
  ]) => [
    for (final d in deinflector.deinflect(surface))
      if (d.base == base &&
          (reasons == null || d.reasons.join(' ') == reasons.join(' ')))
        d,
  ];

  bool anyAccepts(List<Deinflection> ds, String pos) =>
      ds.any((d) => d.acceptsPos([pos]));

  void expectChain(
    String surface,
    String base,
    List<String> reasons,
    String pos,
  ) {
    final found = candidates(surface, base, reasons);
    expect(
      found,
      isNotEmpty,
      reason:
          '$surface should deinflect to $base via $reasons, got '
          '${candidates(surface, base).map((d) => d.reasons).toList()}',
    );
    expect(
      anyAccepts(found, pos),
      isTrue,
      reason: '$surface -> $base must accept $pos, got $found',
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
        final found = candidates('食べる', '食べる', []);
        expect(found, hasLength(1));
        expect(found.single.acceptsPos(['n']), isTrue);
        expect(found.single.acceptsPos(['v1']), isTrue);
      },
    );
  });

  group('polite forms', () {
    test('ます family on ichidan, godan, suru and kuru', () {
      expectChain('食べます', '食べる', ['polite'], 'v1');
      expectChain('食べません', '食べる', ['polite', 'negative'], 'v1');
      expectChain('食べました', '食べる', ['polite', 'past'], 'v1');
      expectChain('食べませんでした', '食べる', ['polite', 'negative', 'past'], 'v1');
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

    test('the iku exception is its own class: 書いて is v5k, 行って is v5k-s', () {
      expect(anyAccepts(candidates('書いて', '書く'), 'v5k-s'), isFalse);
      expect(anyAccepts(candidates('行って', '行く', ['te']), 'v5k'), isFalse);
      expect(anyAccepts(candidates('行きます', '行く'), 'v5k-s'), isTrue);
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
      expectChain('食べましょう', '食べる', ['polite', 'volitional'], 'v1');
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

  group('review additions: classical negatives, contractions, toku, mai', () {
    test('ず, ずに, ぬ, ん are negatives', () {
      expectChain('食べず', '食べる', ['negative'], 'v1');
      expectChain('食べずに', '食べる', ['negative'], 'v1');
      expectChain('知らぬ', '知る', ['negative'], 'v5r');
      expectChain('知らん', '知る', ['negative'], 'v5r');
      expectChain('せずに', 'する', ['negative'], 'vs-i');
      expectChain('せん', 'する', ['negative'], 'vs-i');
      expectChain('来ず', '来る', ['negative'], 'vk');
      expectChain('こん', 'くる', ['negative'], 'vk');
    });

    test('なきゃ, なくちゃ, なくては', () {
      expectChain('食べなきゃ', '食べる', ['negative', 'ba'], 'v1');
      expectChain('食べなくちゃ', '食べる', ['negative', 'te'], 'v1');
      expectChain('行かなくては', '行く', ['negative', 'te'], 'v5k-s');
      expect(candidates('食べなくちゃ', '食べる', ['negative', 'adverb']), isEmpty);
    });

    test('とく/といて/とけ (ておく) and どく', () {
      expectChain('食べとく', '食べる', ['te', 'toku'], 'v1');
      expectChain('食べといて', '食べる', ['te', 'toku'], 'v1');
      expectChain('食べとけ', '食べる', ['te', 'toku'], 'v1');
      expectChain('食べといた', '食べる', ['te', 'toku', 'past'], 'v1');
      expectChain('読んどく', '読む', ['te', 'toku'], 'v5m');
      expectChain('読んどいて', '読む', ['te', 'toku'], 'v5m');
    });

    test('まい after the stem and after the dictionary form', () {
      expectChain('食べまい', '食べる', ['mai'], 'v1');
      expectChain('食べるまい', '食べる', ['mai'], 'v1');
      expectChain('書くまい', '書く', ['mai'], 'v5k');
      expectChain('するまい', 'する', ['mai'], 'vs-i');
    });

    test('potential, passive and causative do not stack', () {
      expect(candidates('食べられられる', '食べる'), isEmpty);
      expect(candidates('食べさせさせる', '食べる'), isEmpty);
      expect(candidates('食べられる', '食ぶ'), isEmpty);
      expect(candidates('書けられる', '書く'), isEmpty);
      // The listed chains still work.
      expectChain('食べさせられる', '食べる', ['causative-passive'], 'v1');
      expectChain('食べられています', '食べる', [
        'potential',
        'te',
        'progressive',
        'polite',
      ], 'v1');
      expectChain('食べさせている', '食べる', ['causative', 'te', 'progressive'], 'v1');
    });
  });

  group('negative cases', () {
    test('a bare masu stem is not a word: たべ does not reach 食べる', () {
      expect(candidates('たべ', 'たべる'), isEmpty);
      expect(candidates('食べ', '食べる'), isEmpty);
    });

    test(
      '本ない does not deinflect to 本, and its verb candidate rejects nouns',
      () {
        expect(candidates('本ない', '本'), isEmpty);
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
        // 食べられる is also the passive of a godan 食べる (as in 取られる),
        // so v5r stays possible; v5k and adj-i are not.
        final found = candidates('食べられなかった', '食べる');
        expect(anyAccepts(found, 'v5k'), isFalse);
        expect(anyAccepts(found, 'adj-i'), isFalse);
        expect(found.any((d) => d.acceptsPos(['n', 'v1'])), isTrue);
      },
    );

    test('katakana input is not special-cased here: the lookup normalises', () {
      expect(candidates('タベタ', 'たべる'), isEmpty);
    });
  });
}
