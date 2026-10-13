/// Typed errors a port implementation may throw. The reader view model maps
/// each one to a user-visible message; nothing else inspects them.
library;

/// Thrown by the `Unavailable…` stand-ins the composition root wires for a
/// port whose real adapter lives on another branch (WP2b, WP3, WP5). It is an
/// [Error], not an [Exception]: a build that reaches it is mis-wired.
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

/// The dictionary could not be opened: the asset is missing from this build
/// (`make dict` was not run) or the on-device copy is unusable. Permanent for
/// this install; [reason] is for the log.
class DictionaryUnavailableError implements Exception {
  const DictionaryUnavailableError(this.reason);

  final String reason;

  @override
  String toString() => 'DictionaryUnavailableError: $reason';
}
