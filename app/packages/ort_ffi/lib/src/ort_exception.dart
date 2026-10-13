part of 'ort.dart';

/// ORT's `OrtErrorCode`, by name. [unknown] covers codes a newer runtime may
/// add; the numeric value is kept in [OrtException.nativeCode] either way.
enum OrtErrorCode {
  ok(b.OrtErrorCode.ORT_OK),
  fail(b.OrtErrorCode.ORT_FAIL),
  invalidArgument(b.OrtErrorCode.ORT_INVALID_ARGUMENT),
  noSuchFile(b.OrtErrorCode.ORT_NO_SUCHFILE),
  noModel(b.OrtErrorCode.ORT_NO_MODEL),
  engineError(b.OrtErrorCode.ORT_ENGINE_ERROR),
  runtimeException(b.OrtErrorCode.ORT_RUNTIME_EXCEPTION),
  invalidProtobuf(b.OrtErrorCode.ORT_INVALID_PROTOBUF),
  modelLoaded(b.OrtErrorCode.ORT_MODEL_LOADED),
  notImplemented(b.OrtErrorCode.ORT_NOT_IMPLEMENTED),
  invalidGraph(b.OrtErrorCode.ORT_INVALID_GRAPH),
  epFail(b.OrtErrorCode.ORT_EP_FAIL),
  modelLoadCanceled(b.OrtErrorCode.ORT_MODEL_LOAD_CANCELED),
  modelRequiresCompilation(b.OrtErrorCode.ORT_MODEL_REQUIRES_COMPILATION),
  notFound(b.OrtErrorCode.ORT_NOT_FOUND),
  unknown(-1);

  const OrtErrorCode(this.native);

  /// The C enum value.
  final int native;

  static OrtErrorCode fromNative(int code) => values.firstWhere(
    (c) => c.native == code,
    orElse: () => OrtErrorCode.unknown,
  );
}

/// A non-OK `OrtStatus`, or a failure of the binding itself (library not
/// loadable, API version not provided). [message] is ORT's own text.
class OrtException implements Exception {
  OrtException(this.code, this.message, {int? nativeCode})
    : nativeCode = nativeCode ?? code.native;

  final OrtErrorCode code;
  final int nativeCode;
  final String message;

  @override
  String toString() => 'OrtException(${code.name} [$nativeCode]): $message';
}
