import 'dart:math' as math;
import 'dart:ui';

/// Intersection over union of two rects: 1 for identical, 0 for disjoint,
/// touching or empty ones.
double rectIou(Rect a, Rect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) {
    return 0;
  }
  final intersection = w * h;
  final union = a.width * a.height + b.width * b.height - intersection;
  return intersection / union;
}
