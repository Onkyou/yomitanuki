import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../domain/errors.dart';
import '../../../domain/models/bgra_image.dart';

/// Decodes an encoded photo (JPEG, PNG, HEIC on iOS) into a [BgraImage] in
/// display orientation, with its longer side at most [maxSide] pixels.
///
/// Flutter's codec applies the EXIF orientation tag while decoding
/// (verified by the EXIF-6 fixture tests, D0.5), so no tag parsing happens
/// here; the only pixel work is the RGBA→BGRA swizzle. The downscale happens
/// inside the codec (`targetWidth`/`targetHeight`), so a 12 MP photo never
/// exists as a 48 MB RGBA buffer plus its BGRA copy: at 3000 px on the long
/// side the two buffers total ~54 MB instead of ~144 MB, and 3000 px keeps
/// the OCR agreement measured in WP0 C7 (3024 px: 92 %).
Future<BgraImage> decodePhoto(List<int> encoded, {int maxSide = 3000}) async {
  final bytes = encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
  final ui.ImmutableBuffer buffer;
  final ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  } on Exception catch (e) {
    throw PhotoDecodeException('$e');
  }
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } on Exception catch (e) {
    buffer.dispose();
    throw PhotoDecodeException('$e');
  }
  try {
    final longest = math.max(descriptor.width, descriptor.height);
    final scale = longest > maxSide ? maxSide / longest : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
      targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba == null) {
          throw const PhotoDecodeException('toByteData returned null');
        }
        return BgraImage(
          width: image.width,
          height: image.height,
          bytes: _rgbaToBgra(rgba.buffer.asUint8List()),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

Uint8List _rgbaToBgra(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    out[i] = rgba[i + 2];
    out[i + 1] = rgba[i + 1];
    out[i + 2] = rgba[i];
    out[i + 3] = rgba[i + 3];
  }
  return out;
}
