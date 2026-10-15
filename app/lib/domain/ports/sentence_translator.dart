import '../models/translation_status.dart';

/// Translates one OCR line from Japanese to English on the device (WP6c). The
/// Apple adapter wraps the Translation framework; every other test uses a
/// fake. Nothing here needs a network.
abstract interface class SentenceTranslator {
  Future<TranslationStatus> status();

  /// The English translation of [line]; the empty string for a blank line.
  /// Throws [TranslationUnavailableError] when the languages are not
  /// installed or the platform cannot translate, and [TranslationFailedError]
  /// when the attempt itself failed.
  Future<String> translate(String line);
}
