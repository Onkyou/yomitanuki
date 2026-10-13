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
  final int classes;

  /// True when at least one JMdict POS tag in [posTags] belongs to a class
  /// in [classes]. The identity candidate accepts everything.
  bool acceptsPos(Iterable<String> posTags) => false;
}

/// The conjugation classes the rule table reasons about. The first group
/// are dictionary-form classes and map onto JMdict POS tags; the rest are
/// intermediate shapes a chain passes through and never match an entry.
enum WordClass { v1 }

class Deinflector {
  const Deinflector();

  List<Deinflection> deinflect(String surface) => const [];
}
