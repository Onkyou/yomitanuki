import '../models/ocr_capture.dart';

/// Keeps OCR crops and their readings for later scoring (D6a.4). A
/// diagnostics aid: [record] never throws, because a failed write must not
/// break reading.
abstract interface class OcrCaptureLog {
  Future<void> record(OcrCapture capture);
}
