import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/ui/reader/view_model/rect_iou.dart';

void main() {
  test('identical rects overlap fully', () {
    const r = Rect.fromLTWH(10, 10, 20, 20);
    expect(rectIou(r, r), 1);
  });

  test('disjoint and merely touching rects do not overlap', () {
    const a = Rect.fromLTWH(0, 0, 10, 10);
    expect(rectIou(a, const Rect.fromLTWH(50, 50, 10, 10)), 0);
    expect(rectIou(a, const Rect.fromLTWH(10, 0, 10, 10)), 0);
  });

  test('half-overlapping equal rects are one third (50 / 150)', () {
    const a = Rect.fromLTWH(0, 0, 10, 10);
    const b = Rect.fromLTWH(5, 0, 10, 10);
    expect(rectIou(a, b), closeTo(1 / 3, 1e-12));
    expect(rectIou(b, a), rectIou(a, b));
  });

  test('a contained rect scores its area ratio', () {
    const outer = Rect.fromLTWH(0, 0, 20, 20);
    const inner = Rect.fromLTWH(5, 5, 10, 10);
    expect(rectIou(outer, inner), closeTo(0.25, 1e-12));
  });

  test('an empty rect scores 0, not NaN', () {
    const a = Rect.fromLTWH(0, 0, 10, 10);
    expect(rectIou(Rect.zero, Rect.zero), 0);
    expect(rectIou(a, Rect.zero), 0);
  });
}
