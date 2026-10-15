/// Typed errors a port implementation may throw. The reader view model maps
/// each one to a user-visible message; nothing else inspects them.
library;

import 'models/translation_status.dart';

/// Thrown by a stand-in wired for a port whose real adapter is not in the
/// build (every port has one since WP2b; the reader tests keep using it as
/// the generic adapter error). It is an [Error], not an [Exception]: a build
/// that reaches it is mis-wired.
class NotWiredError extends Error {
  NotWiredError(this.port);

  /// The port's interface name, e.g. `TextDetector`.
  final String port;

  @override
  String toString() => 'NotWiredError: $port has no adapter in this build';
}

/// The user has refused camera access (or it is restricted by policy).
class CameraPermissionDeniedError implements Exception {
  const CameraPermissionDeniedError();

  @override
  String toString() => 'CameraPermissionDeniedError';
}

/// The camera could not be opened for a reason other than permission: no
/// back camera, the device is in use, a plugin failure. [reason] is a
/// sentence for the user; the plugin's own code is in the adapter's log.
class CameraUnavailableError implements Exception {
  const CameraUnavailableError(this.reason);

  final String reason;

  @override
  String toString() => 'CameraUnavailableError: $reason';
}

/// A picked photo could not be decoded (not an image, or truncated).
/// [reason] is for the log, not the screen.
class PhotoDecodeException implements Exception {
  const PhotoDecodeException(this.reason);

  final String reason;

  @override
  String toString() => 'PhotoDecodeException: $reason';
}

/// The OCR models could not be set up: `assets/models/` is missing from this
/// build (`make models` was not run) or a copied file does not match its
/// manifest. Permanent for this install; [reason] is for the log.
class ModelsUnavailableError implements Exception {
  const ModelsUnavailableError(this.reason);

  final String reason;

  @override
  String toString() => 'ModelsUnavailableError: $reason';
}

/// One detection or recognition pass failed inside the inference adapter
/// (ONNX Runtime's own error, a frame whose geometry does not add up, the
/// worker isolate gone). The next pass may succeed; [reason] is for the log.
class InferenceFailedError implements Exception {
  const InferenceFailedError(this.reason);

  final String reason;

  @override
  String toString() => 'InferenceFailedError: $reason';
}

/// The dictionary could not be opened: the asset is missing from this build
/// (`make dict` was not run) or the on-device copy is unusable. Permanent for
/// this install; [reason] is for the log.
class DictionaryUnavailableError implements Exception {
  const DictionaryUnavailableError(this.reason);

  final String reason;

  @override
  String toString() => 'DictionaryUnavailableError: $reason';
}

/// A line cannot be translated on this device: the language packs are not
/// installed, or the platform is too old or does not support the pair.
/// [status] says which; it is never [TranslationStatus.installed].
class TranslationUnavailableError implements Exception {
  const TranslationUnavailableError(this.status);

  final TranslationStatus status;

  @override
  String toString() => 'TranslationUnavailableError: ${status.name}';
}

/// A translation attempt failed although translating should work (the
/// framework threw, or it answered nothing). The next attempt may succeed;
/// [reason] is for the log.
class TranslationFailedError implements Exception {
  const TranslationFailedError(this.reason);

  final String reason;

  @override
  String toString() => 'TranslationFailedError: $reason';
}
