import '../../../domain/errors.dart';

/// The one place a port error becomes a sentence for the screen. Every port
/// call in the reader view model is caught and routed through here, so no
/// failure in an adapter can take the UI down, and no raw exception text
/// reaches the user: the view model logs the error, the screen gets a fixed
/// sentence.
String describeReaderError(Object error) => switch (error) {
  NotWiredError(:final port) =>
    '$port is not available in this build (its adapter is not wired yet).',
  CameraPermissionDeniedError() =>
    'Camera access is off. Allow it for Yomitanuki in the iOS Settings app.',
  CameraUnavailableError(:final reason) => 'The camera is unavailable: $reason',
  PhotoDecodeException() => 'That image could not be read.',
  _ => 'Something went wrong. Please try again.',
};
