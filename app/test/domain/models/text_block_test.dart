import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/text_block.dart';

void main() {
  test('scaled maps every edge by its axis factor', () {
    const block = TextBlock(
      box: Rect.fromLTRB(10, 20, 30, 60),
      confidence: 0.5,
    );

    expect(
      block.scaled(2, 0.5),
      const TextBlock(box: Rect.fromLTRB(20, 10, 60, 30), confidence: 0.5),
    );
  });

  test('blocks are compared by value', () {
    const a = TextBlock(box: Rect.fromLTRB(0, 0, 1, 1), confidence: 0.9);
    const b = TextBlock(box: Rect.fromLTRB(0, 0, 1, 1), confidence: 0.9);
    const c = TextBlock(box: Rect.fromLTRB(0, 0, 1, 2), confidence: 0.9);

    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(c)));
  });
}
