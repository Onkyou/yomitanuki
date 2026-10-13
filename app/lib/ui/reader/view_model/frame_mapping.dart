import 'dart:math' as math;
import 'dart:ui';

import '../../../domain/models/text_block.dart';

/// The affine map between a frame's pixel coordinates and the preview widget
/// that shows it with `BoxFit.cover`: one uniform [scale] and a centring
/// [offset]. Blocks are detected in frame space; taps arrive in preview
/// space; this is the only place that converts between the two (D4.4).
class FrameMapping {
  const FrameMapping({required this.scale, required this.offset});

  /// The preview shows the whole short side of the frame and crops the long
  /// side symmetrically, exactly what `FittedBox(fit: BoxFit.cover)` draws.
  factory FrameMapping.cover({required Size frame, required Size preview}) {
    final scale = math.max(
      preview.width / frame.width,
      preview.height / frame.height,
    );
    final offset = Offset(
      (preview.width - frame.width * scale) / 2,
      (preview.height - frame.height * scale) / 2,
    );
    return FrameMapping(scale: scale, offset: offset);
  }

  /// The whole frame is visible, letterboxed on the longer axis; for a
  /// still photo, where cropping the page edge would hide bubbles.
  factory FrameMapping.contain({required Size frame, required Size preview}) {
    final scale = math.min(
      preview.width / frame.width,
      preview.height / frame.height,
    );
    final offset = Offset(
      (preview.width - frame.width * scale) / 2,
      (preview.height - frame.height * scale) / 2,
    );
    return FrameMapping(scale: scale, offset: offset);
  }

  final double scale;
  final Offset offset;

  Rect toPreview(Rect frameRect) => Rect.fromLTRB(
    frameRect.left * scale + offset.dx,
    frameRect.top * scale + offset.dy,
    frameRect.right * scale + offset.dx,
    frameRect.bottom * scale + offset.dy,
  );

  Offset toPreviewPoint(Offset framePoint) => framePoint * scale + offset;

  Offset toFrame(Offset previewPoint) => (previewPoint - offset) / scale;

  /// The block under a tap in preview coordinates, or `null`. Every block's
  /// tap target is at least [minTarget] logical pixels on each side, and when
  /// targets overlap the smallest block wins, so a caption inside a bubble
  /// stays tappable.
  TextBlock? blockAt(
    Offset previewPoint,
    Iterable<TextBlock> blocks, {
    double minTarget = 44,
  }) {
    TextBlock? best;
    double? bestArea;
    for (final block in blocks) {
      final r = _withMinimumSize(toPreview(block.box), minTarget);
      if (!r.contains(previewPoint)) {
        continue;
      }
      final area = r.width * r.height;
      if (bestArea == null || area < bestArea) {
        best = block;
        bestArea = area;
      }
    }
    return best;
  }

  static Rect _withMinimumSize(Rect r, double min) {
    final dx = math.max(0.0, (min - r.width) / 2);
    final dy = math.max(0.0, (min - r.height) / 2);
    return Rect.fromLTRB(r.left - dx, r.top - dy, r.right + dx, r.bottom + dy);
  }
}
