import 'dictionary_entry.dart';

/// A dictionary match for the text starting at a tapped character.
class LookupResult {
  const LookupResult({
    required this.start,
    required this.length,
    required this.surface,
    required this.baseForm,
    required this.matchedReading,
    required this.reasons,
    required this.entry,
    required this.matchedSenseIndexes,
  });

  /// Offset of the match in the source string (UTF-16 code units).
  final int start;

  /// Length of the matched surface text in UTF-16 code units.
  final int length;

  /// The matched text as written, e.g. `食べられなかった`.
  final String surface;

  /// The dictionary form the surface deinflects to, e.g. `食べる`.
  final String baseForm;

  /// How the matched form of the entry is read: a kana form reads as itself
  /// as written (ビール, not 麦酒's ばくしゅ), a kanji form as the kana that
  /// applies to it. For an inflected surface it is the base form's reading
  /// (食べた → たべる). WP6b D6b.2.
  final String matchedReading;

  /// The deinflection chain in derivation order, innermost first:
  /// `[potential, negative, past]` for 食べられなかった (食べる → 食べられる →
  /// 食べられない → 食べられなかった). Empty when [surface] is already a
  /// dictionary form. WP3 D3.4.
  final List<String> reasons;
  final DictionaryEntry entry;

  /// Indexes into [DictionaryEntry.senses] of the senses whose part of speech
  /// the deinflection accepts (食べた can only be a v1 sense, 勉強した only
  /// one tagged `vs`). Empty when the entry itself matched exactly: every
  /// sense applies (an exact 勉強する still lists the `vs` senses, because it
  /// is found through the Xする path). Never empty otherwise, the entry was
  /// only kept because at least one sense passed. WP6d D6d.1.
  final List<int> matchedSenseIndexes;
}
