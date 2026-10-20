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
    expect(find.text('ONNX Runtime'), findsOneWidget);
    expect(find.textContaining('MIT License'), findsOneWidget);
  });

  testWidgets('about screen states the deinflection table is its own and '
      'does not call the build private', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutView()));

    // The entry is below the fold on the test surface, so the finders look
    // off-stage too.
    expect(
      find.textContaining(
        'its own deinflection rule table',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('No Yomitan code is used', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Derived from the Yomitan', skipOffstage: false),
      findsNothing,
    );
    expect(
      find.textContaining('not distributed', skipOffstage: false),
      findsNothing,
    );
  });
}
