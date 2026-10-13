import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/main.dart';
import 'package:yomitanuki/ui/home/view/home_view.dart';

void main() {
  testWidgets('YomitanukiApp opens on the home screen', (tester) async {
    await tester.pumpWidget(const YomitanukiApp());

    expect(find.byType(HomeView), findsOneWidget);
  });
}
