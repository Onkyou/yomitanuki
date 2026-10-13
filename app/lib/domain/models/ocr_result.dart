/// The text read from one [TextBlock] crop.
class OcrResult {
  const OcrResult({required this.text, required this.elapsed});

  /// Post-processed text (whitespace stripped, ASCII and digits full-width),
  /// exactly what manga-ocr's own `post_process` produces (WP0 contract).
  final String text;

  final Duration elapsed;
}
