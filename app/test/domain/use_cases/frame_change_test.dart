import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/use_cases/frame_change.dart';

import '../../fakes/images.dart';

/// A [size]x[size] image of one grey level: B = G = R = [value].
BgraImage uniform(int size, int value) {
  final bytes = Uint8List(size * size * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = value;
    bytes[i + 1] = value;
    bytes[i + 2] = value;
    bytes[i + 3] = 255;
  }
  return BgraImage(width: size, height: size, bytes: bytes);
}

int luminanceOfGrey(int v) => (77 * v + 150 * v + 29 * v) >> 8;

void main() {
  group('changedCellFraction', () {
    test('identical frames do not change', () {
      expect(
        changedCellFraction(
          testImage(100, 100, seed: 1),
          testImage(100, 100, seed: 1),
        ),
        0.0,
      );
    });

    test('a one-byte-per-pixel difference between test seeds is still '
        '(why the view model injects the metric)', () {
      expect(
        changedCellFraction(
          testImage(100, 100, seed: 1),
          testImage(100, 100, seed: 2),
        ),
        0.0,
      );
    });

    test('a frame that turned uniformly brighter changed everywhere', () {
      expect(
        changedCellFraction(
          testImage(100, 100, seed: 0),
          testImage(100, 100, seed: 200),
        ),
        1.0,
      );
    });

    test('a change confined to one region changes only its cells', () {
      final before = testImage(100, 100, seed: 0);
      final bytes = Uint8List.fromList(before.bytes);
      for (var y = 0; y < 50; y++) {
        for (var x = 0; x < 50; x++) {
          bytes[y * before.bytesPerRow + x * 4 + 2] = 255;
        }
      }
      final after = BgraImage(width: 100, height: 100, bytes: bytes);
      expect(changedCellFraction(before, after), closeTo(0.25, 0.01));
    });

    test('frames of different sizes count as fully changed', () {
      expect(
        changedCellFraction(testImage(100, 100), testImage(100, 101)),
        1.0,
      );
    });

    test('row padding is honoured', () {
      final packed = testImage(100, 100, seed: 3);
      final paddedRow = 100 * 4 + 16;
      final bytes = Uint8List(paddedRow * 100)
        ..fillRange(0, paddedRow * 100, 0xFF);
      for (var y = 0; y < 100; y++) {
        bytes.setRange(
          y * paddedRow,
          y * paddedRow + 400,
          packed.bytes,
          y * packed.bytesPerRow,
        );
      }
      final padded = BgraImage(
        width: 100,
        height: 100,
        bytes: bytes,
        bytesPerRow: paddedRow,
      );
      expect(changedCellFraction(packed, padded), 0.0);
      expect(changedCellFraction(padded, packed), 0.0);
    });

    test('an image smaller than the grid counts only its non-empty cells', () {
      expect(
        changedCellFraction(
          testImage(10, 10, seed: 0),
          testImage(10, 10, seed: 200),
        ),
        1.0,
      );
      expect(
        changedCellFraction(
          testImage(10, 10, seed: 0),
          testImage(10, 10, seed: 0),
        ),
        0.0,
      );
    });

    test('the threshold is strict', () {
      // Grey levels (low, high) whose luminance differs by exactly [gap].
      (int, int) greysApart(int gap) {
        for (var a = 0; a < 256; a++) {
          for (var b = a + 1; b < 256; b++) {
            if (luminanceOfGrey(b) - luminanceOfGrey(a) == gap) return (a, b);
          }
        }
        fail('no pair of grey levels differs by $gap');
      }

      final (a10, b10) = greysApart(10);
      expect(changedCellFraction(uniform(100, a10), uniform(100, b10)), 0.0);
      final (a11, b11) = greysApart(11);
      expect(changedCellFraction(uniform(100, a11), uniform(100, b11)), 1.0);
    });
  });
}
