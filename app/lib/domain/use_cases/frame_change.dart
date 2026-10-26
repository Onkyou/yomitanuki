import 'dart:typed_data';

import '../models/bgra_image.dart';

/// How much of the picture changed between two frames (D6f.3): the fraction
/// of grid cells whose mean luminance moved by more than [cellThreshold].
///
/// The image is a [grid] x [grid] lattice of cells (integer division, the
/// last cell takes the remainder; cells with no pixels are skipped and not
/// counted). In each cell the pixel at the cell origin and every [stride]
/// pixels after it, in x and in y, are read, so every non-empty cell has at
/// least one sample even on a small image. Frames of different sizes are
/// fully changed (`1.0`); an image with no non-empty cell is `0.0`.
///
/// Cost: at 1080x1920 about 32 k pixel reads per image, well under a
/// millisecond, and no allocation proportional to the image. Luminance is
/// `(77 * r + 150 * g + 29 * b) >> 8`, integer weights summing to 256 so the
/// metric needs no floating point per pixel and is exactly reproducible.
///
/// Pure and synchronous; reads each image's own `bytesPerRow`.
double changedCellFraction(
  BgraImage before,
  BgraImage after, {
  int grid = 24,
  int stride = 8,
  int cellThreshold = 10,
}) {
  if (before.width != after.width || before.height != after.height) return 1.0;
  final width = before.width;
  final height = before.height;
  var counted = 0;
  var changed = 0;
  for (var cy = 0; cy < grid; cy++) {
    final y0 = cy * height ~/ grid;
    final y1 = (cy + 1) * height ~/ grid;
    if (y1 <= y0) continue;
    for (var cx = 0; cx < grid; cx++) {
      final x0 = cx * width ~/ grid;
      final x1 = (cx + 1) * width ~/ grid;
      if (x1 <= x0) continue;
      counted++;
      var sumBefore = 0;
      var sumAfter = 0;
      var samples = 0;
      for (var y = y0; y < y1; y += stride) {
        final rowBefore = y * before.bytesPerRow;
        final rowAfter = y * after.bytesPerRow;
        for (var x = x0; x < x1; x += stride) {
          sumBefore += _luminance(before.bytes, rowBefore + x * 4);
          sumAfter += _luminance(after.bytes, rowAfter + x * 4);
          samples++;
        }
      }
      if ((sumBefore ~/ samples - sumAfter ~/ samples).abs() > cellThreshold) {
        changed++;
      }
    }
  }
  return counted == 0 ? 0.0 : changed / counted;
}

/// Luminance of the BGRA pixel starting at [i].
int _luminance(Uint8List bytes, int i) =>
    (77 * bytes[i + 2] + 150 * bytes[i + 1] + 29 * bytes[i]) >> 8;
