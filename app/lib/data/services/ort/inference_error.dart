/// A request the inference worker could not serve: a frame whose geometry
/// does not add up, the worker disposed or gone while the request was in
/// flight, or an unexpected failure inside the worker (its text in
/// [cause]). ONNX Runtime's own failures arrive as `OrtException` instead;
/// a misuse of the adapter (a call after `dispose()`) is a `StateError`.
///
/// Named "error" after what it reports; it is an [Exception] by Dart's
/// convention because the caller is expected to handle it (show the
/// failure, retry the next frame), not to crash.
class InferenceError implements Exception {
  InferenceError(this.message, {this.cause});

  final String message;

  /// The underlying failure, when the message summarises one.
  final String? cause;

  @override
  String toString() => cause == null
      ? 'InferenceError: $message'
      : 'InferenceError: $message ($cause)';
}
