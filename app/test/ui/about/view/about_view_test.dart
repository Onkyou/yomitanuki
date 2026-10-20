import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/ui/about/view/about_view.dart';

void main() {
  testWidgets('about screen carries every attribution', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutView()));

    expect(find.text('JMdict and KANJIDIC2'), findsOneWidget);
    expect(find.textContaining('(EDRDG)'), findsOneWidget);
    expect(
      find.textContaining('Creative Commons Attribution-ShareAlike 4.0'),
      findsOneWidget,
    );
    expect(find.textContaining('kha-white/manga-ocr'), findsOneWidget);
    expect(find.textContaining('dmMaze/comic-text-detector'), findsOneWidget);
  });

  testWidgets('about screen states the deinflection table is its own and '
      'does not call the build private', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutView()));

    expect(
      find.textContaining('its own deinflection rule table'),
      findsOneWidget,
    );
    expect(find.textContaining('No Yomitan code is used'), findsOneWidget);
    expect(find.textContaining('Derived from the Yomitan'), findsNothing);
    expect(find.textContaining('not distributed'), findsNothing);
  });
}
