import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../domain/models/bgra_image.dart';

/// The platform decoder refused the bytes (not an image, or truncated).
class PhotoDecodeException implements Exception {
  const PhotoDecodeException(this.reason);

  final String reason;

  @override
  String toString() => 'PhotoDecodeException: $reason';
}

/// Decodes an encoded photo (JPEG, PNG, HEIC on iOS) into a [BgraImage] in
/// display orientation. Flutter's codec applies the EXIF orientation tag
/// while decoding (verified by the EXIF-6 fixture test, D0.5), so no tag
/// parsing happens here; the only pixel work is the RGBA→BGRA swizzle.
Future<BgraImage> decodePhoto(List<int> encoded) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(
      encoded is Uint8List ? encoded : Uint8List.fromList(encoded),
    );
  } on Exception catch (e) {
    throw PhotoDecodeException('$e');
  }
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
