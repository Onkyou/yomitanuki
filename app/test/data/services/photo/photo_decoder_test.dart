import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/photo/photo_decoder.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

/// Pixel (x, y) as `[b, g, r, a]`.
List<int> px(BgraImage img, int x, int y) {
  final i = y * img.bytesPerRow + x * 4;
  return img.bytes.sublist(i, i + 4);
}

Future<List<int>> fixture(String name) =>
    File('test/data/services/photo/fixtures/$name').readAsBytes();

void main() {
  // The fixtures were written by PIL (see .claude/wp4/NOTES.md D4.5).
  test('a PNG decodes to BGRA with R and B swapped from RGBA', () async {
    final img = await decodePhoto(await fixture('rgbw_2x2.png'));

    expect((img.width, img.height), (2, 2));
    expect(px(img, 0, 0), [0, 0, 255, 255], reason: 'red');
    expect(px(img, 1, 0), [0, 255, 0, 255], reason: 'green');
    expect(px(img, 0, 1), [255, 0, 0, 255], reason: 'blue');
    expect(px(img, 1, 1), [255, 255, 255, 255], reason: 'white');
  });

  test('a JPEG with EXIF orientation 6 comes out upright (D0.5)', () async {
    // Stored 4x2 with the left half black and the right half white; shown
    // upright it is 2x4 with black on top and white below.
    final img = await decodePhoto(await fixture('exif6_4x2.jpg'));

    expect((img.width, img.height), (2, 4));
    expect(px(img, 0, 0)[0], lessThan(16), reason: 'top is black');
    expect(px(img, 1, 3)[0], greaterThan(240), reason: 'bottom is white');
  });

  test('garbage bytes raise a PhotoDecodeException', () async {
    await expectLater(
      () => decodePhoto([1, 2, 3, 4]),
      throwsA(isA<PhotoDecodeException>()),
    );
  });
}
