import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

void main() {
  // 3x2 image, rows padded to 16 bytes; pixel value = (x, y, 0, 255).
  BgraImage padded() {
    final bytes = Uint8List(2 * 16);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        final i = y * 16 + x * 4;
        bytes[i] = x;
        bytes[i + 1] = y;
        bytes[i + 3] = 255;
      }
    }
    return BgraImage(width: 3, height: 2, bytes: bytes, bytesPerRow: 16);
  }

  test('crop drops row padding and copies the right pixels', () {
    final c = padded().crop(left: 1, top: 0, width: 2, height: 2);

    expect(c.width, 2);
    expect(c.height, 2);
    expect(c.bytesPerRow, 8);
    expect(c.bytes, [1, 0, 0, 255, 2, 0, 0, 255, 1, 1, 0, 255, 2, 1, 0, 255]);
  });

  test('crop clamps to the image bounds', () {
    final c = padded().crop(left: 2, top: 1, width: 10, height: 10);

    expect(c.width, 1);
    expect(c.height, 1);
    expect(c.bytes, [2, 1, 0, 255]);
  });
}
