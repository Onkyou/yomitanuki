part of 'ort.dart';

/// ORT's `GraphOptimizationLevel`.
enum OrtGraphOptimizationLevel {
  disableAll(b.GraphOptimizationLevel.ORT_DISABLE_ALL),
  basic(b.GraphOptimizationLevel.ORT_ENABLE_BASIC),
  extended(b.GraphOptimizationLevel.ORT_ENABLE_EXTENDED),
  layout(b.GraphOptimizationLevel.ORT_ENABLE_LAYOUT),
  all(b.GraphOptimizationLevel.ORT_ENABLE_ALL);

  const OrtGraphOptimizationLevel(this.native);

  final int native;
}

/// `OrtSessionOptions`: thread count, graph optimisation level and execution
/// providers. Configure before [OrtSession.fromFile]; ORT copies the options
/// into the session, so the object can be disposed right after.
class OrtSessionOptions {
  /// Creates options with ORT's defaults (all cores, all optimisations, CPU).
  OrtSessionOptions(this._runtime) {
    final api = _runtime._checkedApi;
    final out = calloc<Pointer<b.OrtSessionOptions>>();
    try {
      api.check(api.createSessionOptions(out));
      _options = out.value;
    } finally {
      calloc.free(out);
    }
  }

  final OrtRuntime _runtime;
  late Pointer<b.OrtSessionOptions> _options;
  bool _disposed = false;

  Pointer<b.OrtSessionOptions> get _checked {
    if (_disposed) {
      throw StateError('OrtSessionOptions has been disposed');
    }
    return _options;
  }

  /// Threads used inside one operator (ORT `intra_op_num_threads`).
  void setIntraOpThreads(int threads) {
    final api = _runtime._checkedApi;
    api.check(api.setIntraOpNumThreads(_checked, threads));
  }

  void setGraphOptimizationLevel(OrtGraphOptimizationLevel level) {
    final api = _runtime._checkedApi;
    api.check(api.setSessionGraphOptimizationLevel(_checked, level.native));
  }

  /// Safe to call twice.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtime._api.releaseSessionOptions(_options);
    _options = nullptr;
  }
}
