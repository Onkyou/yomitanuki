import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/ui/reader/view/block_overlay.dart';

void main() {
  const a = Rect.fromLTWH(0, 0, 10, 10);
  const b = Rect.fromLTWH(5, 5, 10, 10);

  test('shouldRepaint is true when the boxes change', () {
    const old = BlockOverlayPainter(boxes: [a], color: Colors.red);

    expect(
      const BlockOverlayPainter(
        boxes: [b],
        color: Colors.red,
      ).shouldRepaint(old),
      isTrue,
    );
    expect(
      const BlockOverlayPainter(
        boxes: [a, b],
        color: Colors.red,
      ).shouldRepaint(old),
      isTrue,
    );
  });

  test('shouldRepaint is true when the selection or colour changes', () {
    const old = BlockOverlayPainter(boxes: [a], color: Colors.red);

    expect(
      const BlockOverlayPainter(
        boxes: [a],
        color: Colors.red,
        selected: a,
      ).shouldRepaint(old),
      isTrue,
    );
    expect(
      const BlockOverlayPainter(
        boxes: [a],
        color: Colors.blue,
      ).shouldRepaint(old),
      isTrue,
    );
  });

  test('shouldRepaint is false for equal inputs', () {
    const old = BlockOverlayPainter(boxes: [a, b], color: Colors.red);

    expect(
      const BlockOverlayPainter(
        boxes: [a, b],
        color: Colors.red,
      ).shouldRepaint(old),
      isFalse,
    );
  });
}
