import 'package:yomitanuki/domain/models/ocr_capture.dart';
import 'package:yomitanuki/domain/ports/ocr_capture_log.dart';

/// Collects every record, oldest first, so a test can assert on what the
/// reader asked to have saved.
class FakeOcrCaptureLog implements OcrCaptureLog {
  final List<OcrCapture> records = [];

  @override
  Future<void> record(OcrCapture capture) async {
    records.add(capture);
  }
}
