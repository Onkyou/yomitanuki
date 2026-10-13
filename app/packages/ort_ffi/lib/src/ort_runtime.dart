part of 'ort.dart';

/// The ONNX Runtime library and its `OrtEnv`.
///
/// Open one per isolate that runs inference (ORT shares a single environment
/// per process underneath, reference counted; a second [OrtRuntime] in
/// another isolate is cheap). Values, options and sessions are created
/// through it and must be disposed before it; [dispose] is idempotent.
///
/// macOS (`flutter test`): [OrtRuntime.open] with the dylib `make ort-macos`
/// fetched. iOS: [OrtRuntime.process], the runtime is linked into the app by
/// the `onnxruntime-c` pod (see `ios/ort_ffi.podspec`).
class OrtRuntime {
  OrtRuntime._(this._bindings, this._api, this._env, this._cpuMemoryInfo);

  /// The `ORT_API_VERSION` requested from `OrtApiBase.GetApi`.
  ///
  /// 30, not the 31 of the header the bindings come from: the iOS pod is
  /// 1.30.0 (1.31.0 is not on CocoaPods) and the macOS dylib is 1.31.0. The
  /// `OrtApi` struct is append-only, so requesting the lower version is valid
  /// against both, and nothing this package calls was added after 30.
  static const int apiVersion = 30;

  /// Opens the runtime from a shared library at [libraryPath].
  factory OrtRuntime.open(String libraryPath) {
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(libraryPath);
    } on ArgumentError catch (e) {
      throw OrtException(
        OrtErrorCode.fail,
        'ONNX Runtime could not be loaded from $libraryPath: ${e.message}',
      );
    }
    return OrtRuntime._fromBindings(b.OnnxRuntimeBindings(library));
  }

  /// Opens the runtime that is linked into the running process (iOS).
  ///
  /// Looks for `OrtGetApiBase` and, failing that, the plugin's own
  /// `ort_ffi_get_api_base` (ios/Classes/ort_ffi.m), which exists exactly so
  /// that the static onnxruntime-c library is linked and reachable.
  factory OrtRuntime.process() {
    final process = DynamicLibrary.process();
    Pointer<T> lookup<T extends NativeType>(String symbol) {
      if (symbol == 'OrtGetApiBase' &&
          !process.providesSymbol(symbol) &&
          process.providesSymbol('ort_ffi_get_api_base')) {
        return process.lookup<T>('ort_ffi_get_api_base');
      }
      return process.lookup<T>(symbol);
    }

    return OrtRuntime._fromBindings(b.OnnxRuntimeBindings.fromLookup(lookup));
  }

  static OrtRuntime _fromBindings(b.OnnxRuntimeBindings bindings) {
    final Pointer<b.OrtApiBase> base;
    try {
      base = bindings.OrtGetApiBase();
    } on ArgumentError catch (e) {
      throw OrtException(
        OrtErrorCode.fail,
        'OrtGetApiBase is not exported by the loaded library: ${e.message}',
      );
    }
    final apiPointer = base.ref.GetApi
        .asFunction<Pointer<b.OrtApi> Function(int)>()(apiVersion);
    if (apiPointer == nullptr) {
      throw OrtException(
        OrtErrorCode.fail,
        'ONNX Runtime ${_versionOf(base)} does not provide C API version '
        '$apiVersion',
      );
    }
    final api = _OrtApi(apiPointer);
    final env = calloc<Pointer<b.OrtEnv>>();
    final memoryInfo = calloc<Pointer<b.OrtMemoryInfo>>();
    final logId = 'yomitanuki'.toNativeUtf8();
    try {
      api.check(
        api.createEnv(
          b.OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
          logId.cast(),
          env,
        ),
      );
      try {
        api.check(
          api.createCpuMemoryInfo(
            b.OrtAllocatorType.OrtArenaAllocator,
            b.OrtMemType.OrtMemTypeDefault,
            memoryInfo,
          ),
        );
      } on OrtException {
        api.releaseEnv(env.value);
        rethrow;
      }
      return OrtRuntime._(bindings, api, env.value, memoryInfo.value);
    } finally {
      calloc.free(logId);
      calloc.free(memoryInfo);
      calloc.free(env);
    }
  }

  static String _versionOf(Pointer<b.OrtApiBase> base) => base
      .ref
      .GetVersionString
      .asFunction<Pointer<Char> Function()>()()
      .cast<Utf8>()
      .toDartString();

  final b.OnnxRuntimeBindings _bindings;
  final _OrtApi _api;
  Pointer<b.OrtEnv> _env;
  Pointer<b.OrtMemoryInfo> _cpuMemoryInfo;
  bool _disposed = false;

  /// The linked ONNX Runtime's version string, e.g. `1.31.0`.
  String get version => _versionOf(_bindings.OrtGetApiBase());

  bool get isDisposed => _disposed;

  _OrtApi get _checkedApi {
    if (_disposed) {
      throw StateError('OrtRuntime has been disposed');
    }
    return _api;
  }

  Pointer<b.OrtEnv> get _checkedEnv {
    _checkedApi;
    return _env;
  }

  /// Releases the environment. Safe to call twice.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _api.releaseMemoryInfo(_cpuMemoryInfo);
    _cpuMemoryInfo = nullptr;
    _api.releaseEnv(_env);
    _env = nullptr;
  }
}
