part of 'ort.dart';

/// Name, element type and shape of one graph input or output. Symbolic or
/// unknown dimensions are `-1`.
class OrtTensorInfo {
  const OrtTensorInfo({
    required this.name,
    required this.elementType,
    required this.shape,
  });

  final String name;
  final OrtElementType elementType;
  final List<int> shape;

  @override
  String toString() => 'OrtTensorInfo($name: ${elementType.name} $shape)';
}

/// An `OrtSession` loaded from a file. Metadata is read once at load time;
/// [run] is synchronous and should be called from a worker isolate.
class OrtSession {
  OrtSession._(this._runtime, this._session, this.inputInfo, this.outputInfo);

  /// Loads the model at [path] with [options] (which may be disposed
  /// afterwards; ORT copies them).
  factory OrtSession.fromFile(String path, OrtSessionOptions options) {
    final runtime = options._runtime;
    final api = runtime._checkedApi;
    final env = runtime._checkedEnv;
    final nativePath = path.toNativeUtf8();
    final out = calloc<Pointer<b.OrtSession>>();
    final Pointer<b.OrtSession> session;
    try {
      api.check(
        api.createSession(env, nativePath.cast(), options._checked, out),
      );
      session = out.value;
    } finally {
      calloc.free(out);
      calloc.free(nativePath);
    }
    try {
      final inputs = _tensorInfos(
        api,
        session,
        api.sessionGetInputCount,
        api.sessionGetInputName,
        api.sessionGetInputTypeInfo,
      );
      final outputs = _tensorInfos(
        api,
        session,
        api.sessionGetOutputCount,
        api.sessionGetOutputName,
        api.sessionGetOutputTypeInfo,
      );
      _refuseAliasedOutputs(inputs, outputs);
      return OrtSession._(runtime, session, inputs, outputs);
    } on OrtException {
      api.releaseSession(session);
      rethrow;
    }
  }

  /// A graph output that IS a graph input (no node in between) makes ORT
  /// hand the input `OrtValue` back from `Run` without allocating, so the
  /// fetched value would share the caller's buffer and die with the input
  /// (D2.12). No model this app ships does that; refuse rather than alias.
  static void _refuseAliasedOutputs(
    List<OrtTensorInfo> inputs,
    List<OrtTensorInfo> outputs,
  ) {
    final inputNames = {for (final i in inputs) i.name};
    final aliased = [
      for (final o in outputs)
        if (inputNames.contains(o.name)) o.name,
    ];
    if (aliased.isNotEmpty) {
      throw OrtException(
        OrtErrorCode.invalidGraph,
        'graph output(s) ${aliased.map((n) => "'$n'").join(', ')} are also '
        'graph inputs; ort_ffi does not support outputs that alias inputs',
      );
    }
  }

  final OrtRuntime _runtime;
  Pointer<b.OrtSession> _session;
  bool _disposed = false;

  /// Graph inputs in graph order.
  final List<OrtTensorInfo> inputInfo;

  /// Graph outputs in graph order.
  final List<OrtTensorInfo> outputInfo;

  List<String> get inputNames => [for (final i in inputInfo) i.name];

  List<String> get outputNames => [for (final o in outputInfo) o.name];

  Pointer<b.OrtSession> get _checked {
    if (_disposed) {
      throw StateError('OrtSession has been disposed');
    }
    return _session;
  }

  /// Runs the graph on [inputs] (graph input name to value) and returns the
  /// outputs named in [outputNames] (default: all, each name at most once),
  /// keyed by name. The caller owns the returned values and disposes them;
  /// they never share memory with the inputs ([OrtSession.fromFile] refuses a
  /// graph whose output is an input, D2.12), so inputs may be disposed first.
  Map<String, OrtValue> run(
    Map<String, OrtValue> inputs, {
    List<String>? outputNames,
  }) {
    final session = _checked;
    final api = _runtime._checkedApi;
    final inputList = inputs.entries.toList();
    final outputList = outputNames ?? this.outputNames;
    if (outputList.toSet().length != outputList.length) {
      throw ArgumentError.value(
        outputNames,
        'outputNames',
        'contains a duplicate; each output can be fetched once per run',
      );
    }
    final inputNamesNative = calloc<Pointer<Char>>(inputList.length);
    final inputValues = calloc<Pointer<b.OrtValue>>(inputList.length);
    final outputNamesNative = calloc<Pointer<Char>>(outputList.length);
    final outputValues = calloc<Pointer<b.OrtValue>>(outputList.length);
    try {
      for (var i = 0; i < inputList.length; i++) {
        inputNamesNative[i] = inputList[i].key.toNativeUtf8().cast();
        inputValues[i] = inputList[i].value._checked;
      }
      for (var i = 0; i < outputList.length; i++) {
        outputNamesNative[i] = outputList[i].toNativeUtf8().cast();
      }
      try {
        api.check(
          api.run(
            session,
            nullptr,
            inputNamesNative,
            inputValues,
            inputList.length,
            outputNamesNative,
            outputList.length,
            outputValues,
          ),
        );
      } on OrtException {
        for (var i = 0; i < outputList.length; i++) {
          if (outputValues[i] != nullptr) {
            api.releaseValue(outputValues[i]);
          }
        }
        rethrow;
      }
      return {
        for (var i = 0; i < outputList.length; i++)
          outputList[i]: OrtValue._(_runtime, outputValues[i], null),
      };
    } finally {
      for (var i = 0; i < inputList.length; i++) {
        calloc.free(inputNamesNative[i]);
      }
      for (var i = 0; i < outputList.length; i++) {
        calloc.free(outputNamesNative[i]);
      }
      calloc.free(outputValues);
      calloc.free(outputNamesNative);
      calloc.free(inputValues);
      calloc.free(inputNamesNative);
    }
  }

  /// Safe to call twice.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtime._api.releaseSession(_session);
    _session = nullptr;
  }

  static List<OrtTensorInfo> _tensorInfos(
    _OrtApi api,
    Pointer<b.OrtSession> session,
    _Status Function(Pointer<b.OrtSession>, Pointer<Size>) getCount,
    _Status Function(
      Pointer<b.OrtSession>,
      int,
      Pointer<b.OrtAllocator>,
      Pointer<Pointer<Char>>,
    )
    getName,
    _Status Function(
      Pointer<b.OrtSession>,
      int,
      Pointer<Pointer<b.OrtTypeInfo>>,
    )
    getTypeInfo,
  ) {
    final count = calloc<Size>();
    final allocator = calloc<Pointer<b.OrtAllocator>>();
    try {
      api.check(getCount(session, count));
      api.check(api.getAllocatorWithDefaultOptions(allocator));
      return [
        for (var i = 0; i < count.value; i++)
          switch (_typeInfo(api, session, i, getTypeInfo)) {
            (final elementType, final shape) => OrtTensorInfo(
              name: _name(api, session, i, allocator.value, getName),
              elementType: elementType,
              shape: shape,
            ),
          },
      ];
    } finally {
      calloc.free(allocator);
      calloc.free(count);
    }
  }

  static String _name(
    _OrtApi api,
    Pointer<b.OrtSession> session,
    int index,
    Pointer<b.OrtAllocator> allocator,
    _Status Function(
      Pointer<b.OrtSession>,
      int,
      Pointer<b.OrtAllocator>,
      Pointer<Pointer<Char>>,
    )
    getName,
  ) {
    final out = calloc<Pointer<Char>>();
    try {
      api.check(getName(session, index, allocator, out));
      try {
        return out.value.cast<Utf8>().toDartString();
      } finally {
        api.check(api.allocatorFree(allocator, out.value.cast()));
      }
    } finally {
      calloc.free(out);
    }
  }

  static (OrtElementType, List<int>) _typeInfo(
    _OrtApi api,
    Pointer<b.OrtSession> session,
    int index,
    _Status Function(
      Pointer<b.OrtSession>,
      int,
      Pointer<Pointer<b.OrtTypeInfo>>,
    )
    getTypeInfo,
  ) {
    final typeInfo = calloc<Pointer<b.OrtTypeInfo>>();
    final tensorInfo = calloc<Pointer<b.OrtTensorTypeAndShapeInfo>>();
    final type = calloc<UnsignedInt>();
    final dimCount = calloc<Size>();
    try {
      api.check(getTypeInfo(session, index, typeInfo));
      try {
        // The tensor info is owned by the type info; only the latter is
        // released. A non-tensor input (map, sequence) casts to null.
        api.check(api.castTypeInfoToTensorInfo(typeInfo.value, tensorInfo));
        if (tensorInfo.value == nullptr) {
          return (OrtElementType.other, const []);
        }
        api.check(api.getTensorElementType(tensorInfo.value, type));
        api.check(api.getDimensionsCount(tensorInfo.value, dimCount));
        final dims = calloc<Int64>(dimCount.value);
        try {
          api.check(api.getDimensions(tensorInfo.value, dims, dimCount.value));
          return (
            OrtElementType.fromNative(type.value),
            List<int>.generate(dimCount.value, (i) => dims[i]),
          );
        } finally {
          calloc.free(dims);
        }
      } finally {
        api.releaseTypeInfo(typeInfo.value);
      }
    } finally {
      calloc.free(dimCount);
      calloc.free(type);
      calloc.free(tensorInfo);
      calloc.free(typeInfo);
    }
  }
}
