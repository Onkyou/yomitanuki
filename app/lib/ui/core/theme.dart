import 'package:flutter/material.dart';

/// The one seed colour; light and dark themes derive from it.
const seedColor = Colors.brown;

ThemeData lightTheme() => ThemeData(colorSchemeSeed: seedColor);

ThemeData darkTheme() =>
    ThemeData(colorSchemeSeed: seedColor, brightness: Brightness.dark);

/// The colour of the boxes drawn over the camera preview. It is the LIGHT
/// scheme's primary whatever the app theme is: what lies under the boxes is
/// a paper page, not the app's surface, so the dark scheme's pale primary
/// would wash out on it.
final Color overlayColor = ColorScheme.fromSeed(seedColor: seedColor).primary;
