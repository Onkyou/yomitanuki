import '../models/bgra_image.dart';
import '../models/ocr_result.dart';

/// Reads the text of one block crop. Implemented by the ONNX adapter (WP2)
/// and by fakes in every other test. Must not run on the UI isolate.
abstract interface class OcrEngine {
  Future<OcrResult> recognise(BgraImage crop);

  Future<void> dispose();
}
