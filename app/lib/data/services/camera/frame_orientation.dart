import 'dart:typed_data';

import '../../../domain/models/bgra_image.dart';

/// Rotates [src] 90 degrees clockwise into a new, tightly packed image: the
/// source's left column becomes the top row (read bottom-up). This is what
/// turns a landscape sensor buffer of the back camera into the portrait frame
/// the preview shows (D4.3).
BgraImage rotateCw90(BgraImage src) {
  final w = src.width;
  final h = src.height;
  final out = Uint8List(w * h * 4);
  final input = src.bytes;
  final outRow = h * 4;
  for (var y = 0; y < h; y++) {
    final srcRow = y * src.bytesPerRow;
    // Source row y becomes destination column (h - 1 - y).
    final dstCol = (h - 1 - y) * 4;
    for (var x = 0; x < w; x++) {
      final s = srcRow + x * 4;
      final d = x * outRow + dstCol;
      out[d] = input[s];
      out[d + 1] = input[s + 1];
      out[d + 2] = input[s + 2];
      out[d + 3] = input[s + 3];
    }
  }
  return BgraImage(width: h, height: w, bytes: out);
}

/// A frame in portrait display orientation: a landscape buffer is rotated,
/// anything else is returned as is (no copy). The camera plugin on iOS already
/// rotates its video output to the locked capture orientation, so the common
/// case is the pass-through; the rotation covers a plugin or platform that
/// delivers sensor orientation instead (D4.3).
BgraImage orientForPortrait(BgraImage frame) =>
    frame.width > frame.height ? rotateCw90(frame) : frame;
