import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/ui/home/view/home_view.dart';

void main() {
  testWidgets('HomeView renders the title Yomitanuki', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeView()));

    expect(find.text('Yomitanuki'), findsOneWidget);
  });
}
