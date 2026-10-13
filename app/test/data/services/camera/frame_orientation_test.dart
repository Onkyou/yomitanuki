import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/camera/frame_orientation.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

/// Pixel (x, y) of [img] as `[b, g, r, a]`.
List<int> px(BgraImage img, int x, int y) {
  final i = y * img.bytesPerRow + x * 4;
  return img.bytes.sublist(i, i + 4);
}

void main() {
  // A 3x2 landscape frame, rows padded to 16 bytes, pixel = (x, y, 9, 255):
  //   (0,0) (1,0) (2,0)
  //   (0,1) (1,1) (2,1)
  BgraImage landscape() {
    final bytes = Uint8List(2 * 16);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        bytes.setRange(y * 16 + x * 4, y * 16 + x * 4 + 4, [x, y, 9, 255]);
      }
    }
    return BgraImage(width: 3, height: 2, bytes: bytes, bytesPerRow: 16);
  }

  test('rotateCw90 turns a 3x2 landscape frame into a 2x3 portrait one', () {
    final r = rotateCw90(landscape());

    expect(r.width, 2);
    expect(r.height, 3);
    expect(r.bytesPerRow, 8, reason: 'output is tightly packed');
    // Clockwise: the source's left column becomes the top row, read from the
    // bottom of the column upwards, so (0,1) lands at (0,0) and (0,0) at (1,0).
    expect(px(r, 0, 0), [0, 1, 9, 255]);
    expect(px(r, 1, 0), [0, 0, 9, 255]);
    expect(px(r, 0, 1), [1, 1, 9, 255]);
    expect(px(r, 1, 1), [1, 0, 9, 255]);
    expect(px(r, 0, 2), [2, 1, 9, 255]);
    expect(px(r, 1, 2), [2, 0, 9, 255]);
  });

  test('orientForPortrait rotates a landscape frame', () {
    final r = orientForPortrait(landscape());

    expect((r.width, r.height), (2, 3));
    expect(px(r, 1, 0), [0, 0, 9, 255]);
  });

  test('orientForPortrait passes a portrait frame through without copying', () {
    final portrait = rotateCw90(landscape());

    final r = orientForPortrait(portrait);

    expect(identical(r, portrait), isTrue);
  });

  test('orientForPortrait leaves a square frame alone', () {
    final square = BgraImage(width: 1, height: 1, bytes: Uint8List(4));

    expect(identical(orientForPortrait(square), square), isTrue);
  });
}
