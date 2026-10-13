import 'dart:typed_data';

import 'package:yomitanuki/domain/models/bgra_image.dart';

/// A [width]x[height] image where every pixel is `(b, g, r, a)` =
/// `(x & 0xff, y & 0xff, seed & 0xff, 255)`, so crops can be checked pixel by
/// pixel and two frames with different [seed]s are distinguishable.
BgraImage testImage(int width, int height, {int seed = 0}) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      bytes[i] = x & 0xff;
      bytes[i + 1] = y & 0xff;
      bytes[i + 2] = seed & 0xff;
      bytes[i + 3] = 255;
    }
  }
  return BgraImage(width: width, height: height, bytes: bytes);
}
