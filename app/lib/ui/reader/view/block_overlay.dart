import 'package:flutter/material.dart';

/// Rounded boxes over the preview, one per detected block, already in
/// preview coordinates. Styling does not depend on confidence (the reader
/// taps what is boxed; a faint box would only invite a tap that fails).
class BlockOverlayPainter extends CustomPainter {
  const BlockOverlayPainter({
    required this.boxes,
    required this.color,
    this.selected,
    this.strokeWidth = 2.5,
    this.radius = 10,
  });

  final List<Rect> boxes;
  final Color color;

  /// The box being read, drawn filled so the reader sees which one.
  final Rect? selected;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.12);
    final selectedFill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.35);
    final r = Radius.circular(radius);
    for (final box in boxes) {
      final rrect = RRect.fromRectAndRadius(box, r);
      canvas.drawRRect(rrect, box == selected ? selectedFill : fill);
      canvas.drawRRect(rrect, stroke);
    }
  }

  @override
  bool shouldRepaint(BlockOverlayPainter old) =>
      old.color != color ||
      old.selected != selected ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius ||
      !_sameBoxes(old.boxes, boxes);

  static bool _sameBoxes(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
