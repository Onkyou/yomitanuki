import '../models/dictionary_entry.dart';
import '../models/lookup_result.dart';

/// JMdict + KANJIDIC2 lookups (WP3).
abstract interface class Dictionary {
  /// Every match for text starting at [index] in [text], longest surface
  /// first, deinflected forms included (WP0 C15: scan from the tapped
  /// character, never pre-segment the line).
  Future<List<LookupResult>> lookupAt(String text, int index);

  Future<KanjiEntry?> kanji(String literal);
}
