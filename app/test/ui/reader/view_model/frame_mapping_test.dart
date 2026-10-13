import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/ui/reader/view_model/frame_mapping.dart';

void main() {
  // A 1080x1920 portrait frame shown in a 390x844 preview with BoxFit.cover:
  // the frame is scaled by max(390/1080, 844/1920) = 0.4396 to 474.7x844 and
  // centred, so 42.4 px are cut off on each side.
  const frame = Size(1080, 1920);
  const preview = Size(390, 844);

  test('cover: scale fills the preview and centres the overflow', () {
    final m = FrameMapping.cover(frame: frame, preview: preview);

    expect(m.scale, closeTo(844 / 1920, 1e-9));
    expect(m.offset.dx, closeTo((390 - 1080 * 844 / 1920) / 2, 1e-9));
    expect(m.offset.dy, closeTo(0, 1e-9));
  });

  test('contain: the whole frame is visible, letterboxed vertically', () {
    // A 4:3 landscape photo in the same portrait preview.
    final m = FrameMapping.contain(
      frame: const Size(4000, 3000),
      preview: preview,
    );

    expect(m.scale, closeTo(390 / 4000, 1e-9));
    expect(m.offset.dx, closeTo(0, 1e-9));
    expect(m.offset.dy, closeTo((844 - 3000 * 390 / 4000) / 2, 1e-9));
  });

  test('toPreview maps a frame block onto preview coordinates', () {
    final m = FrameMapping.cover(frame: frame, preview: preview);
    const block = TextBlock(
      box: Rect.fromLTWH(540, 960, 200, 100),
      confidence: 0.5,
    );

    final r = m.toPreview(block.box);

    expect(r.left, closeTo(540 * m.scale + m.offset.dx, 1e-9));
    expect(r.top, closeTo(960 * m.scale, 1e-9));
    expect(r.width, closeTo(200 * m.scale, 1e-9));
    expect(r.height, closeTo(100 * m.scale, 1e-9));
  });

  test('toFrame inverts toPreview', () {
    final m = FrameMapping.cover(frame: frame, preview: preview);
    const p = Offset(123.4, 567.8);

    final back = m.toPreviewPoint(m.toFrame(p));

    expect(back.dx, closeTo(p.dx, 1e-9));
    expect(back.dy, closeTo(p.dy, 1e-9));
  });

  group('blockAt', () {
    final m = FrameMapping.cover(
      frame: const Size(100, 100),
      preview: const Size(100, 100),
    );
    const big = TextBlock(box: Rect.fromLTWH(10, 10, 60, 60), confidence: 0.9);
    const small = TextBlock(
      box: Rect.fromLTWH(20, 20, 10, 10),
      confidence: 0.8,
    );
    const tiny = TextBlock(box: Rect.fromLTWH(80, 80, 4, 4), confidence: 0.7);

    test('picks the smallest block containing the tap', () {
      expect(m.blockAt(const Offset(25, 25), [big, small]), small);
      expect(m.blockAt(const Offset(50, 50), [big, small]), big);
    });

    test('misses when the tap is outside every block', () {
      expect(m.blockAt(const Offset(95, 5), [big, small]), isNull);
    });

    test('a tiny block still has a tap target of at least minTarget', () {
      // tiny is 4 px wide; with minTarget 24 it accepts taps up to 10 px away.
      expect(m.blockAt(const Offset(72, 72), [tiny], minTarget: 24), tiny);
      expect(m.blockAt(const Offset(60, 60), [tiny], minTarget: 24), isNull);
    });
  });
}
