import '../../../domain/models/bgra_image.dart';

/// One still photo from the library, decoded and already in display
/// orientation (D0.5), as the fallback to the live camera (D10).
///
/// Not a domain port: the domain's `FrameSource` is the camera; this is the
/// one-shot alternative the reader offers and WP4 owns both sides of it
/// (`.claude/wp4/NOTES.md` D4.6).
abstract interface class PhotoPicker {
  /// `null` when the user cancels the picker.
  Future<BgraImage?> pickPhoto();
}
