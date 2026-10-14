import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/ui/reader/view/bgra_image_view.dart';
import 'package:yomitanuki/ui/reader/view/ocr_sheet.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_state.dart';

import '../../../fakes/images.dart';

const _block = TextBlock(box: Rect.fromLTWH(10, 10, 20, 20), confidence: 0.9);

Future<void> _pumpSheet(WidgetTester tester, OcrState state) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: OcrSheet(
            ocrState: state,
            lookupState: const LookupIdle(),
            onTapCharacter: (_) {},
            onAddToAnki: (_) {},
            onClose: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  final crop = testImage(40, 60);

  testWidgets('shows the crop in a 96 px box while reading', (tester) async {
    await _pumpSheet(tester, OcrRunning(_block, crop));

    final box = find.byKey(const Key('ocr.crop'));
    expect(box, findsOneWidget);
    expect(tester.getSize(box).height, 96);
    expect(
      tester.widget<BgraImageView>(find.byType(BgraImageView)).image,
      crop,
    );
  });

  testWidgets('keeps showing the crop with the text', (tester) async {
    await _pumpSheet(tester, OcrText(_block, crop, '食べる'));

    expect(find.byKey(const Key('ocr.crop')), findsOneWidget);
    expect(find.byKey(const Key('ocr.char.0')), findsOneWidget);
  });

  testWidgets('keeps showing the crop with the failure', (tester) async {
    await _pumpSheet(tester, OcrFailed(_block, crop, 'Could not read'));

    expect(find.byKey(const Key('ocr.crop')), findsOneWidget);
    expect(find.text('Could not read'), findsOneWidget);
  });

  testWidgets('no crop when idle', (tester) async {
    await _pumpSheet(tester, const OcrIdle());

    expect(find.byKey(const Key('ocr.crop')), findsNothing);
  });
}
