import 'bgra_image.dart';

/// What one diagnostic capture holds: the crop the OCR engine was given and
/// how it was read, so a reading can be scored against the pixels later
/// (D6a.5).
class OcrCapture {
  const OcrCapture({
    required this.crop,
    required this.frameWidth,
    required this.frameHeight,
    required this.text,
    required this.elapsed,
    required this.at,
  });

  final BgraImage crop;

  /// The size of the frame the crop was cut from; crop width relative to it
  /// is what the accuracy question turns on.
  final int frameWidth;
  final int frameHeight;

  /// Empty when the read failed.
  final String text;

  /// `Duration.zero` when the read failed.
  final Duration elapsed;

  /// When the reading landed (the view model's clock), not when the bubble
  /// was tapped. Names the PNG and fills the `timestamp` column.
  final DateTime at;
}
