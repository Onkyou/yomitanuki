import '../models/bgra_image.dart';

/// Live camera frames (WP4). The preview widget is the adapter's concern; the
/// domain only sees frames.
abstract interface class FrameSource {
  /// Frames as the camera delivers them, already in display orientation.
  /// Consumers sample this at their own cadence (D0.13: ~1 frame/s).
  Stream<BgraImage> get frames;

  Future<void> start();

  Future<void> stop();
}
