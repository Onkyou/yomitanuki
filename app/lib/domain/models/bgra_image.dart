import 'dart:typed_data';

/// A raw 8-bit BGRA image, the layout the iOS camera delivers and the layout
/// every ONNX graph in this app consumes directly (WP0 D0.9).
///
/// [bytesPerRow] may exceed `width * 4` when rows are padded.
class BgraImage {
  const BgraImage({
    required this.width,
    required this.height,
    required this.bytes,
    int? bytesPerRow,
  }) : bytesPerRow = bytesPerRow ?? width * 4;

  final int width;
  final int height;
  final int bytesPerRow;
  final Uint8List bytes;

  /// A copy of the rectangle [left],[top],[width],[height], tightly packed
  /// (no row padding). Coordinates are clamped to the image.
  BgraImage crop({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final x0 = left.clamp(0, this.width);
    final y0 = top.clamp(0, this.height);
    final x1 = (left + width).clamp(x0, this.width);
    final y1 = (top + height).clamp(y0, this.height);
    final w = x1 - x0;
    final h = y1 - y0;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final src = (y0 + y) * bytesPerRow + x0 * 4;
      out.setRange(y * w * 4, (y + 1) * w * 4, bytes, src);
    }
    return BgraImage(width: w, height: h, bytes: out);
  }
}
