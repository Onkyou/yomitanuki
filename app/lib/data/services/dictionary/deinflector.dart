/// Rule-based Japanese deinflection (PLAN.md P3), own rule table.
///
/// A surface such as 食べられなかった is peeled one suffix at a time:
/// なかった→ない (past), ない→る (negative), られる→る (potential), and the
/// chain is bounded by [Deinflector.maxDepth]. Every rule records the shape
/// the string must have before the rule applies (`from`) and the shape it
/// has afterwards (`to`), so a chain is only accepted when the shapes line
/// up: ない only strips off an adjective-shaped string, a masu stem is only
/// reached through a stem suffix like ます or たい, and the final shape names
/// the JMdict part-of-speech classes the entry must carry.
///
/// Reasons use short English names (`past`, `negative`, `potential`, …);
/// they are data for the UI, not grammar.
library;

/// One candidate dictionary form for an inflected surface.
class Deinflection {
  const Deinflection({
    required this.base,
    required this.reasons,
    required this.classes,
  });

  /// The candidate dictionary form, e.g. `食べる`.
  final String base;

  /// Reasons in derivation order, innermost first: `[potential, negative,
  /// past]` for 食べられなかった. Empty for the surface itself.
  final List<String> reasons;

  /// The word classes the dictionary entry must belong to for this
  /// candidate to be valid, as a bitmask over [WordClass.index].
  /// [anyClass] for the identity candidate.
  final int classes;

  /// The identity candidate accepts every entry.
  static const int anyClass = -1;

  /// True when at least one JMdict POS tag in [posTags] belongs to a class
  /// in [classes]. The identity candidate accepts everything.
  bool acceptsPos(Iterable<String> posTags) {
    if (classes == anyClass) {
      return true;
    }
    for (final tag in posTags) {
      final cls = WordClass.ofPosTag(tag);
      if (cls != null && classes & cls.bit != 0) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString() =>
      'Deinflection($base, $reasons, ${WordClass.describe(classes)})';
}

/// The conjugation classes the rule table reasons about. The first group
/// are dictionary-form classes and map onto JMdict POS tags; the last three
/// are intermediate shapes a chain passes through and never match an entry.
enum WordClass {
  v1(['v1', 'v1-s']),
  v5k(['v5k']),
  v5ks(['v5k-s']),
  v5g(['v5g']),
  v5s(['v5s']),
  v5t(['v5t']),
  v5n(['v5n']),
  v5b(['v5b']),
  v5m(['v5m']),
  v5r(['v5r', 'v5r-i']),
  v5u(['v5u', 'v5u-s']),
  adjI(['adj-i', 'adj-ix']),
  vk(['vk']),
  vs(['vs-i', 'vs-s', 'vs']),

  /// A て/で form, e.g. 食べて, 読んで, 強くて.
  te([]),

  /// A 連用形 (masu stem), e.g. 食べ, 書き, し, 来. Only reachable through a
  /// stem suffix (ます, たい, そう, …), never from the bare surface.
  stem([]),

  /// A finite form that can only be the outermost layer (past, polite,
  /// imperative, volitional, conditional, そう, さ, く).
  terminal([]);

  const WordClass(this.posTags);

  /// The JMdict POS tags that belong to this class.
  final List<String> posTags;

  int get bit => 1 << index;

  static final Map<String, WordClass> _byTag = {
    for (final cls in values)
      for (final tag in cls.posTags) tag: cls,
  };

  static WordClass? ofPosTag(String tag) => _byTag[tag];

  static String describe(int mask) {
    if (mask == Deinflection.anyClass) {
      return 'any';
    }
    return [
      for (final cls in values)
        if (mask & cls.bit != 0) cls.name,
    ].join('|');
  }
}

class _Rule {
  const _Rule(
    this.suffix,
    this.replacement,
    this.reasons, {
    required this.from,
    required this.to,
  });

  final String suffix;
  final String replacement;

  /// Outermost first, the order the search peels them off.
  final List<String> reasons;
  final int from;
  final int to;
}

/// One godan column: the dictionary ending and its a/i/e/o-row kana plus the
/// 音便 stem used by て/た forms.
class _Godan {
  const _Godan(
    this.cls,
    this.u,
    this.a,
    this.i,
    this.e,
    this.o,
    this.teStem, {
    this.voiced = false,
  });

  final WordClass cls;
  final String u;
  final String a;
  final String i;
  final String e;
  final String o;
  final String teStem;
  final bool voiced;
}

class _Node {
  const _Node(this.text, this.reasonsOuterFirst, this.classes, this.depth);

  final String text;
  final List<String> reasonsOuterFirst;
  final int classes;
  final int depth;
}

class Deinflector {
  const Deinflector();

  /// Longest chain of rules a surface is allowed to go through.
  static const int maxDepth = 6;

  static final int _v1 = WordClass.v1.bit;
  static final int _adjI = WordClass.adjI.bit;
  static final int _vk = WordClass.vk.bit;
  static final int _vs = WordClass.vs.bit;
  static final int _te = WordClass.te.bit;
  static final int _stem = WordClass.stem.bit;
  static final int _terminal = WordClass.terminal.bit;
  static final int _v5u = WordClass.v5u.bit;
  static final int _v5kAny = WordClass.v5k.bit | WordClass.v5ks.bit;

  /// The shapes a bare surface may have: any dictionary form, a て form or
  /// a terminal form. Never a masu stem.
  static final int _initial = [
    for (final cls in WordClass.values)
      if (cls != WordClass.stem) cls.bit,
  ].fold(0, (a, b) => a | b);

  static const List<_Godan> _godan = [
    _Godan(WordClass.v5k, 'く', 'か', 'き', 'け', 'こ', 'い'),
    _Godan(WordClass.v5g, 'ぐ', 'が', 'ぎ', 'げ', 'ご', 'い', voiced: true),
    _Godan(WordClass.v5s, 'す', 'さ', 'し', 'せ', 'そ', 'し'),
    _Godan(WordClass.v5t, 'つ', 'た', 'ち', 'て', 'と', 'っ'),
    _Godan(WordClass.v5n, 'ぬ', 'な', 'に', 'ね', 'の', 'ん', voiced: true),
    _Godan(WordClass.v5b, 'ぶ', 'ば', 'び', 'べ', 'ぼ', 'ん', voiced: true),
    _Godan(WordClass.v5m, 'む', 'ま', 'み', 'め', 'も', 'ん', voiced: true),
    _Godan(WordClass.v5r, 'る', 'ら', 'り', 'れ', 'ろ', 'っ'),
    _Godan(WordClass.v5u, 'う', 'わ', 'い', 'え', 'お', 'っ'),
  ];

  static final List<_Rule> _rules = _buildRules();

  /// Rules indexed by the last UTF-16 code unit of their suffix, so a node
  /// only tries the rules that can match it. The stem rules have an empty
  /// suffix and are tried on every node of stem shape.
  static final Map<int, List<_Rule>> _rulesByLastUnit = _index(_rules);
  static final List<_Rule> _emptySuffixRules = [
    for (final rule in _rules)
      if (rule.suffix.isEmpty) rule,
  ];

  /// Classes that can match a JMdict entry; a result is only emitted when
  /// its shape intersects this.
  static final int _dictionaryMask = [
    for (final cls in WordClass.values)
      if (cls.posTags.isNotEmpty) cls.bit,
  ].fold(0, (a, b) => a | b);

  static Map<int, List<_Rule>> _index(List<_Rule> rules) {
    final map = <int, List<_Rule>>{};
    for (final rule in rules) {
      if (rule.suffix.isEmpty) {
        continue;
      }
      map
          .putIfAbsent(rule.suffix.codeUnitAt(rule.suffix.length - 1), () => [])
          .add(rule);
    }
    return map;
  }

  static List<_Rule> _buildRules() {
    final rules = <_Rule>[];

    // Rules are listed potential-before-passive so that an ambiguous られる
    // shows as potential first; a lookup dedupes per entry and keeps the
    // first candidate.
    _addIchidan(rules);
    for (final g in _godan) {
      _addGodan(rules, g);
    }
    _addIku(rules);
    _addKuru(rules);
    _addSuru(rules);
    _addAdjective(rules);
    _addStemSuffixes(rules);
    _addTeSuffixes(rules);
    return rules;
  }

  static void _addIchidan(List<_Rule> rules) {
    final v1 = _v1;
    rules.addAll([
      _Rule('て', 'る', ['te'], from: _te, to: v1),
      _Rule('た', 'る', ['past'], from: _terminal, to: v1),
      _Rule('たら', 'る', ['tara'], from: _terminal, to: v1),
      _Rule('たり', 'る', ['tari'], from: _terminal, to: v1),
      _Rule('ない', 'る', ['negative'], from: _adjI, to: v1),
      _Rule('られる', 'る', ['potential'], from: _v1, to: v1),
      _Rule('れる', 'る', ['potential'], from: _v1, to: v1),
      _Rule('られる', 'る', ['passive'], from: _v1, to: v1),
      _Rule('させる', 'る', ['causative'], from: _v1, to: v1),
      _Rule('させられる', 'る', ['causative-passive'], from: _v1, to: v1),
      _Rule('ろ', 'る', ['imperative'], from: _terminal, to: v1),
      _Rule('よ', 'る', ['imperative'], from: _terminal, to: v1),
      _Rule('れば', 'る', ['ba'], from: _terminal, to: v1),
      _Rule('よう', 'る', ['volitional'], from: _terminal, to: v1),
      _Rule('', 'る', const [], from: _stem, to: v1),
    ]);
  }

  static void _addGodan(List<_Rule> rules, _Godan g) {
    // 行く conjugates as v5k everywhere except in its て/た stem, so the
    // regular rows also produce the v5k-s class; the て/た rules do not.
    final to = g.cls == WordClass.v5k ? _v5kAny : g.cls.bit;
    final te = g.voiced ? 'で' : 'て';
    final ta = g.voiced ? 'だ' : 'た';
    rules.addAll([
      _Rule('${g.teStem}$te', g.u, ['te'], from: _te, to: g.cls.bit),
      _Rule('${g.teStem}$ta', g.u, ['past'], from: _terminal, to: g.cls.bit),
      _Rule('${g.teStem}$taら', g.u, ['tara'], from: _terminal, to: g.cls.bit),
      _Rule('${g.teStem}$taり', g.u, ['tari'], from: _terminal, to: g.cls.bit),
      _Rule('${g.a}ない', g.u, ['negative'], from: _adjI, to: to),
      _Rule('${g.e}る', g.u, ['potential'], from: _v1, to: to),
      _Rule('${g.a}れる', g.u, ['passive'], from: _v1, to: to),
      _Rule('${g.a}せる', g.u, ['causative'], from: _v1, to: to),
      _Rule('${g.a}せられる', g.u, ['causative-passive'], from: _v1, to: to),
      if (g.cls != WordClass.v5s)
        _Rule('${g.a}される', g.u, ['causative-passive'], from: _v1, to: to),
      _Rule(g.e, g.u, ['imperative'], from: _terminal, to: to),
      _Rule('${g.e}ば', g.u, ['ba'], from: _terminal, to: to),
      _Rule('${g.o}う', g.u, ['volitional'], from: _terminal, to: to),
      _Rule(g.i, g.u, const [], from: _stem, to: to),
    ]);
  }

  /// 行く/いく: the only godan whose て/た stem is っ although it ends in く.
  static void _addIku(List<_Rule> rules) {
    final to = WordClass.v5ks.bit;
    for (final (iku, stem) in [('行く', '行'), ('いく', 'い'), ('ゆく', 'ゆ')]) {
      rules.addAll([
        _Rule('$stemって', iku, ['te'], from: _te, to: to),
        _Rule('$stemった', iku, ['past'], from: _terminal, to: to),
        _Rule('$stemったら', iku, ['tara'], from: _terminal, to: to),
        _Rule('$stemったり', iku, ['tari'], from: _terminal, to: to),
      ]);
    }
  }

  static void _addKuru(List<_Rule> rules) {
    final vk = _vk;
    for (final (kuru, ki, ko) in [('来る', '来', '来'), ('くる', 'き', 'こ')]) {
      final ku = kuru.substring(0, kuru.length - 1);
      rules.addAll([
        _Rule('$kiて', kuru, ['te'], from: _te, to: vk),
        _Rule('$kiた', kuru, ['past'], from: _terminal, to: vk),
        _Rule('$kiたら', kuru, ['tara'], from: _terminal, to: vk),
        _Rule('$kiたり', kuru, ['tari'], from: _terminal, to: vk),
        _Rule('$koない', kuru, ['negative'], from: _adjI, to: vk),
        _Rule('$koられる', kuru, ['potential'], from: _v1, to: vk),
        _Rule('$koれる', kuru, ['potential'], from: _v1, to: vk),
        _Rule('$koられる', kuru, ['passive'], from: _v1, to: vk),
        _Rule('$koさせる', kuru, ['causative'], from: _v1, to: vk),
        _Rule('$koさせられる', kuru, ['causative-passive'], from: _v1, to: vk),
        _Rule('$koい', kuru, ['imperative'], from: _terminal, to: vk),
        _Rule('$kuれば', kuru, ['ba'], from: _terminal, to: vk),
        _Rule('$koよう', kuru, ['volitional'], from: _terminal, to: vk),
        _Rule(ki, kuru, const [], from: _stem, to: vk),
      ]);
    }
  }

  static void _addSuru(List<_Rule> rules) {
    final vs = _vs;
    rules.addAll([
      _Rule('して', 'する', ['te'], from: _te, to: vs),
      _Rule('した', 'する', ['past'], from: _terminal, to: vs),
      _Rule('したら', 'する', ['tara'], from: _terminal, to: vs),
      _Rule('したり', 'する', ['tari'], from: _terminal, to: vs),
      _Rule('しない', 'する', ['negative'], from: _adjI, to: vs),
      _Rule('できる', 'する', ['potential'], from: _v1, to: vs),
      _Rule('出来る', 'する', ['potential'], from: _v1, to: vs),
      _Rule('される', 'する', ['passive'], from: _v1, to: vs),
      _Rule('させる', 'する', ['causative'], from: _v1, to: vs),
      _Rule('させられる', 'する', ['causative-passive'], from: _v1, to: vs),
      _Rule('しろ', 'する', ['imperative'], from: _terminal, to: vs),
      _Rule('せよ', 'する', ['imperative'], from: _terminal, to: vs),
      _Rule('すれば', 'する', ['ba'], from: _terminal, to: vs),
      _Rule('しよう', 'する', ['volitional'], from: _terminal, to: vs),
      _Rule('し', 'する', const [], from: _stem, to: vs),
    ]);
  }

  static void _addAdjective(List<_Rule> rules) {
    final adjI = _adjI;
    rules.addAll([
      _Rule('くて', 'い', ['te'], from: _te, to: adjI),
      _Rule('かった', 'い', ['past'], from: _terminal, to: adjI),
      _Rule('かったら', 'い', ['tara'], from: _terminal, to: adjI),
      _Rule('かったり', 'い', ['tari'], from: _terminal, to: adjI),
      _Rule('くない', 'い', ['negative'], from: _adjI, to: adjI),
      _Rule('ければ', 'い', ['ba'], from: _terminal, to: adjI),
      _Rule('く', 'い', ['adverb'], from: _terminal, to: adjI),
      _Rule('そう', 'い', ['sou'], from: _terminal, to: adjI),
      _Rule('さ', 'い', ['sa'], from: _terminal, to: adjI),
      _Rule('すぎる', 'い', ['sugiru'], from: _v1, to: adjI),
    ]);
  }

  /// Suffixes that attach to the 連用形; the stem rules above turn the
  /// remainder back into a dictionary form without adding a reason.
  static void _addStemSuffixes(List<_Rule> rules) {
    rules.addAll([
      _Rule('ます', '', ['polite'], from: _terminal, to: _stem),
      _Rule('ません', '', ['negative', 'polite'], from: _terminal, to: _stem),
      _Rule('ました', '', ['past', 'polite'], from: _terminal, to: _stem),
      _Rule(
        'ませんでした',
        '',
        ['past', 'negative', 'polite'],
        from: _terminal,
        to: _stem,
      ),
      _Rule('ましょう', '', ['volitional', 'polite'], from: _terminal, to: _stem),
      _Rule('なさい', '', ['nasai'], from: _terminal, to: _stem),
      _Rule('ながら', '', ['nagara'], from: _terminal, to: _stem),
      _Rule('そう', '', ['sou'], from: _terminal, to: _stem),
      _Rule('すぎる', '', ['sugiru'], from: _v1, to: _stem),
      _Rule('たい', '', ['tai'], from: _adjI, to: _stem),
    ]);
  }

  /// Auxiliaries that attach to the て form.
  static void _addTeSuffixes(List<_Rule> rules) {
    rules.addAll([
      _Rule('ている', 'て', ['progressive'], from: _v1, to: _te),
      _Rule('でいる', 'で', ['progressive'], from: _v1, to: _te),
      _Rule('てる', 'て', ['progressive'], from: _v1, to: _te),
      _Rule('でる', 'で', ['progressive'], from: _v1, to: _te),
      _Rule('ちゃう', 'て', ['chau'], from: _v5u, to: _te),
      _Rule('じゃう', 'で', ['chau'], from: _v5u, to: _te),
      _Rule('てしまう', 'て', ['shimau'], from: _v5u, to: _te),
      _Rule('でしまう', 'で', ['shimau'], from: _v5u, to: _te),
    ]);
  }

  /// Every candidate dictionary form for [surface], the surface itself
  /// first, then by chain length and rule order.
  List<Deinflection> deinflect(String surface) {
    if (surface.isEmpty) {
      return const [];
    }
    final results = <Deinflection>[
      Deinflection(
        base: surface,
        reasons: const [],
        classes: Deinflection.anyClass,
      ),
    ];
    var frontier = <_Node>[_Node(surface, const [], _initial, 0)];
    while (frontier.isNotEmpty) {
      final next = <_Node>[];
      for (final node in frontier) {
        _expand(node, results, next);
      }
      frontier = next;
    }
    return results;
  }

  void _expand(_Node node, List<Deinflection> results, List<_Node> next) {
    final text = node.text;
    // The stem rules have an empty suffix; the others are indexed by last unit.
    final candidates = <_Rule>[
      ...?_rulesByLastUnit[text.codeUnitAt(text.length - 1)],
      ..._emptySuffixRules,
    ];
    for (final rule in candidates) {
      if (node.classes & rule.from == 0 || !text.endsWith(rule.suffix)) {
        continue;
      }
      final base =
          text.substring(0, text.length - rule.suffix.length) +
          rule.replacement;
      if (base.isEmpty) {
        continue;
      }
      final reasons = [...node.reasonsOuterFirst, ...rule.reasons];
      if (rule.to & _dictionaryMask != 0) {
        results.add(
          Deinflection(
            base: base,
            reasons: reasons.reversed.toList(growable: false),
            classes: rule.to,
          ),
        );
      }
      if (node.depth + 1 < maxDepth) {
        next.add(_Node(base, reasons, rule.to, node.depth + 1));
      }
    }
  }
}
