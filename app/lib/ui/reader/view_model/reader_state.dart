import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/models/text_block.dart';

/// Where the frame on screen comes from.
enum ReaderSource { camera, photo }

sealed class CameraState {
  const CameraState();
}

/// Not started, or stopped (also while a photo is shown).
final class CameraIdle extends CameraState {
  const CameraIdle();
}

final class CameraStarting extends CameraState {
  const CameraStarting();
}

final class CameraLive extends CameraState {
  const CameraLive();
}

final class CameraFailed extends CameraState {
  const CameraFailed(this.message, {this.permissionDenied = false});

  final String message;

  /// True when the fix is in the iOS Settings app, not in a retry.
  final bool permissionDenied;
}

sealed class OcrState {
  const OcrState();
}

final class OcrIdle extends OcrState {
  const OcrIdle();
}

final class OcrRunning extends OcrState {
  const OcrRunning(this.block);

  final TextBlock block;
}

final class OcrText extends OcrState {
  const OcrText(this.block, this.text);

  final TextBlock block;
  final String text;
}

final class OcrFailed extends OcrState {
  const OcrFailed(this.block, this.message);

  final TextBlock block;
  final String message;
}

sealed class LookupState {
  const LookupState();
}

final class LookupIdle extends LookupState {
  const LookupIdle();
}

final class LookupLoading extends LookupState {
  const LookupLoading(this.index);

  /// The tapped character, UTF-16 offset into the OCR text.
  final int index;
}

final class LookupResults extends LookupState {
  const LookupResults({
    required this.index,
    required this.results,
    required this.kanji,
  });

  final int index;

  /// Longest surface first, as the port returns them. Empty = no match.
  final List<LookupResult> results;

  /// Every kanji that occurs in a matched surface, keyed by literal.
  final Map<String, KanjiEntry> kanji;
}

final class LookupFailed extends LookupState {
  const LookupFailed(this.index, this.message);

  final int index;
  final String message;
}

/// One-shot outcome of an "Add to Anki" tap; the view shows it once and calls
/// `consumeAnkiMessage()`.
sealed class AnkiMessage {
  const AnkiMessage();
}

final class AnkiHandedOver extends AnkiMessage {
  const AnkiHandedOver(this.word);

  final String word;
}

final class AnkiNotInstalled extends AnkiMessage {
  const AnkiNotInstalled();
}

final class AnkiFailed extends AnkiMessage {
  const AnkiFailed(this.message);

  final String message;
}
