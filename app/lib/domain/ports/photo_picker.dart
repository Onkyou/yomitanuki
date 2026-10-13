import '../models/bgra_image.dart';

/// One still photo from the library, decoded and already in display
/// orientation (D0.5): the fallback to the live camera (D10, WP4).
/// Implemented by the `image_picker` adapter and by a fake in every other
/// test.
abstract interface class PhotoPicker {
  /// `null` when the user cancels the picker.
  Future<BgraImage?> pickPhoto();
}
