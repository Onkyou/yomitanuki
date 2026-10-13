import '../models/bgra_image.dart';
import '../models/text_block.dart';

/// Finds text blocks on a page image. Implemented by the ONNX adapter (WP2)
/// and by fakes in every other test. Must not run on the UI isolate.
abstract interface class TextDetector {
  /// Blocks in [image]'s pixel coordinates, highest confidence first.
  Future<List<TextBlock>> detect(BgraImage image);

  Future<void> dispose();
}
