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
/// back camera, the device is in use, a plugin failure.
class CameraUnavailableError implements Exception {
  const CameraUnavailableError(this.reason);

  final String reason;

  @override
  String toString() => 'CameraUnavailableError: $reason';
}
