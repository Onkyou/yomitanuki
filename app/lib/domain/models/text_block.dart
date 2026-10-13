import 'dart:ui';

/// One detected text region (a speech bubble, a caption, a sound effect), in
/// the pixel coordinates of the image it was detected on.
class TextBlock {
  const TextBlock({required this.box, required this.confidence});

  final Rect box;

  /// Detector confidence in `[0, 1]`.
  final double confidence;

  /// The same block in an image scaled by [sx] horizontally and [sy]
  /// vertically, e.g. to map detector coordinates onto a preview widget.
  TextBlock scaled(double sx, double sy) => TextBlock(
    box: Rect.fromLTRB(
      box.left * sx,
      box.top * sy,
      box.right * sx,
      box.bottom * sy,
    ),
    confidence: confidence,
  );

  @override
  bool operator ==(Object other) =>
      other is TextBlock && other.box == box && other.confidence == confidence;

  @override
  int get hashCode => Object.hash(box, confidence);

  @override
  String toString() => 'TextBlock($box, ${confidence.toStringAsFixed(2)})';
}
