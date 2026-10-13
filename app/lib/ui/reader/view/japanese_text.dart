import 'package:flutter/material.dart';

/// Fonts that render Japanese well on iOS (Hiragino ships with the system);
/// the Noto names cover a later Android build. Used for every run of
/// Japanese text so kanji never fall back to a CJK-less face.
const japaneseFontFallback = [
  'Hiragino Sans',
  'Hiragino Kaku Gothic ProN',
  'Noto Sans CJK JP',
  'Noto Sans JP',
];

extension JapaneseTextStyle on TextStyle {
  TextStyle get japanese => copyWith(fontFamilyFallback: japaneseFontFallback);
}
