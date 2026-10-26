import '../models/bgra_image.dart';

/// Live camera frames (WP4). The preview widget is the adapter's concern; the
/// domain only sees frames.
abstract interface class FrameSource {
  /// Frames as the camera delivers them, already in display orientation.
  /// Consumers ask for a frame with [requestFrame] and get it here.
  Stream<BgraImage> get frames;

  /// The consumer asks for the next frame. The source delivers one frame per
  /// outstanding request on [frames]; requests made before the delivery
  /// coalesce into one. A request the source cannot answer (the stream
  /// failed to start) surfaces as an error on [frames].
  void requestFrame();

  Future<void> start();

  Future<void> stop();
}
