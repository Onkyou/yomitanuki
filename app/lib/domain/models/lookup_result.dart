import 'dictionary_entry.dart';

/// A dictionary match for the text starting at a tapped character.
class LookupResult {
  const LookupResult({
    required this.start,
    required this.length,
    required this.surface,
    required this.baseForm,
    required this.reasons,
    required this.entry,
  });

  /// Offset of the match in the source string (UTF-16 code units).
  final int start;

  /// Length of the matched surface text in UTF-16 code units.
  final int length;

  /// The matched text as written, e.g. `食べられなかった`.
  final String surface;

  /// The dictionary form the surface deinflects to, e.g. `食べる`.
  final String baseForm;

  /// The deinflection chain, outermost first, e.g. `[past, negative, potential]`.
  /// Empty when [surface] is already a dictionary form.
  final List<String> reasons;
  final DictionaryEntry entry;
}
