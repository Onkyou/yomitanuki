part of 'ort.dart';

typedef _Status = Pointer<b.OrtStatus>;

/// The members of the `OrtApi` struct this package calls, bound once per
/// runtime as Dart functions (`asFunction` builds a trampoline; doing it per
/// call would cost on every `run`).
///
/// Every ORT call that returns a status goes through [check], which releases
/// the status and throws [OrtException] with ORT's message.
class _OrtApi {
  _OrtApi(this._api);

  final Pointer<b.OrtApi> _api;

  b.OrtApi get _ref => _api.ref;

  late final getErrorCode =
      _ref.GetErrorCode.asFunction<int Function(_Status)>();
  late final getErrorMessage =
      _ref.GetErrorMessage.asFunction<Pointer<Char> Function(_Status)>();
  late final releaseStatus =
      _ref.ReleaseStatus.asFunction<void Function(_Status)>();

  late final createEnv =
      _ref.CreateEnv.asFunction<
        _Status Function(int, Pointer<Char>, Pointer<Pointer<b.OrtEnv>>)
      >();
  late final releaseEnv =
      _ref.ReleaseEnv.asFunction<void Function(Pointer<b.OrtEnv>)>();

  late final createSessionOptions =
      _ref.CreateSessionOptions.asFunction<
        _Status Function(Pointer<Pointer<b.OrtSessionOptions>>)
      >();
  late final setIntraOpNumThreads =
      _ref.SetIntraOpNumThreads.asFunction<
        _Status Function(Pointer<b.OrtSessionOptions>, int)
      >();
  late final setSessionGraphOptimizationLevel =
      _ref.SetSessionGraphOptimizationLevel.asFunction<
        _Status Function(Pointer<b.OrtSessionOptions>, int)
      >();
  late final sessionOptionsAppendExecutionProvider =
      _ref.SessionOptionsAppendExecutionProvider.asFunction<
        _Status Function(
          Pointer<b.OrtSessionOptions>,
          Pointer<Char>,
          Pointer<Pointer<Char>>,
          Pointer<Pointer<Char>>,
          int,
        )
      >();
  late final releaseSessionOptions =
      _ref.ReleaseSessionOptions.asFunction<
        void Function(Pointer<b.OrtSessionOptions>)
      >();

  late final createSession =
      _ref.CreateSession.asFunction<
        _Status Function(
          Pointer<b.OrtEnv>,
          Pointer<Char>,
          Pointer<b.OrtSessionOptions>,
          Pointer<Pointer<b.OrtSession>>,
        )
      >();
  late final sessionGetInputCount =
      _ref.SessionGetInputCount.asFunction<
        _Status Function(Pointer<b.OrtSession>, Pointer<Size>)
      >();
  late final sessionGetOutputCount =
      _ref.SessionGetOutputCount.asFunction<
        _Status Function(Pointer<b.OrtSession>, Pointer<Size>)
      >();
  late final sessionGetInputName =
      _ref.SessionGetInputName.asFunction<
        _Status Function(
          Pointer<b.OrtSession>,
          int,
          Pointer<b.OrtAllocator>,
          Pointer<Pointer<Char>>,
        )
      >();
  late final sessionGetOutputName =
      _ref.SessionGetOutputName.asFunction<
        _Status Function(
          Pointer<b.OrtSession>,
          int,
          Pointer<b.OrtAllocator>,
          Pointer<Pointer<Char>>,
        )
      >();
  late final sessionGetInputTypeInfo =
      _ref.SessionGetInputTypeInfo.asFunction<
        _Status Function(
          Pointer<b.OrtSession>,
          int,
          Pointer<Pointer<b.OrtTypeInfo>>,
        )
      >();
  late final sessionGetOutputTypeInfo =
      _ref.SessionGetOutputTypeInfo.asFunction<
        _Status Function(
          Pointer<b.OrtSession>,
          int,
          Pointer<Pointer<b.OrtTypeInfo>>,
        )
      >();
  late final run =
      _ref.Run.asFunction<
        _Status Function(
          Pointer<b.OrtSession>,
          Pointer<b.OrtRunOptions>,
          Pointer<Pointer<Char>>,
          Pointer<Pointer<b.OrtValue>>,
          int,
          Pointer<Pointer<Char>>,
          int,
          Pointer<Pointer<b.OrtValue>>,
        )
      >();
  late final releaseSession =
      _ref.ReleaseSession.asFunction<void Function(Pointer<b.OrtSession>)>();

  late final castTypeInfoToTensorInfo =
      _ref.CastTypeInfoToTensorInfo.asFunction<
        _Status Function(
          Pointer<b.OrtTypeInfo>,
          Pointer<Pointer<b.OrtTensorTypeAndShapeInfo>>,
        )
      >();
  late final releaseTypeInfo =
      _ref.ReleaseTypeInfo.asFunction<void Function(Pointer<b.OrtTypeInfo>)>();
  late final getTensorElementType =
      _ref.GetTensorElementType.asFunction<
        _Status Function(
          Pointer<b.OrtTensorTypeAndShapeInfo>,
          Pointer<UnsignedInt>,
        )
      >();
  late final getDimensionsCount =
      _ref.GetDimensionsCount.asFunction<
        _Status Function(Pointer<b.OrtTensorTypeAndShapeInfo>, Pointer<Size>)
      >();
  late final getDimensions =
      _ref.GetDimensions.asFunction<
        _Status Function(
          Pointer<b.OrtTensorTypeAndShapeInfo>,
          Pointer<Int64>,
          int,
        )
      >();
  late final getTensorShapeElementCount =
      _ref.GetTensorShapeElementCount.asFunction<
        _Status Function(Pointer<b.OrtTensorTypeAndShapeInfo>, Pointer<Size>)
      >();
  late final getTensorTypeAndShape =
      _ref.GetTensorTypeAndShape.asFunction<
        _Status Function(
          Pointer<b.OrtValue>,
          Pointer<Pointer<b.OrtTensorTypeAndShapeInfo>>,
        )
      >();
  late final releaseTensorTypeAndShapeInfo =
      _ref.ReleaseTensorTypeAndShapeInfo.asFunction<
        void Function(Pointer<b.OrtTensorTypeAndShapeInfo>)
      >();

  late final createCpuMemoryInfo =
      _ref.CreateCpuMemoryInfo.asFunction<
        _Status Function(int, int, Pointer<Pointer<b.OrtMemoryInfo>>)
      >();
  late final releaseMemoryInfo = _ref
      .ReleaseMemoryInfo.asFunction<void Function(Pointer<b.OrtMemoryInfo>)>();
  late final createTensorWithDataAsOrtValue =
      _ref.CreateTensorWithDataAsOrtValue.asFunction<
        _Status Function(
          Pointer<b.OrtMemoryInfo>,
          Pointer<Void>,
          int,
          Pointer<Int64>,
          int,
          int,
          Pointer<Pointer<b.OrtValue>>,
        )
      >();
  late final getTensorMutableData =
      _ref.GetTensorMutableData.asFunction<
        _Status Function(Pointer<b.OrtValue>, Pointer<Pointer<Void>>)
      >();
  late final releaseValue =
      _ref.ReleaseValue.asFunction<void Function(Pointer<b.OrtValue>)>();

  late final getAllocatorWithDefaultOptions =
      _ref.GetAllocatorWithDefaultOptions.asFunction<
        _Status Function(Pointer<Pointer<b.OrtAllocator>>)
      >();
  late final allocatorFree =
      _ref.AllocatorFree.asFunction<
        _Status Function(Pointer<b.OrtAllocator>, Pointer<Void>)
      >();

  /// Throws [OrtException] for a non-null status, releasing it first.
  void check(_Status status) {
    if (status == nullptr) {
      return;
    }
    final code = getErrorCode(status);
    final message = getErrorMessage(status).cast<Utf8>().toDartString();
    releaseStatus(status);
    throw OrtException(
      OrtErrorCode.fromNative(code),
      message,
      nativeCode: code,
    );
  }
}
