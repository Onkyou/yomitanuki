part of 'ort.dart';

/// ORT's `ONNXTensorElementDataType`, by name; the three this package can
/// create and read are [float32], [uint8] and [int64]. [other] covers the
/// rest, so metadata of any graph can still be listed.
enum OrtElementType {
  undefined(
    b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED,
  ),
  float32(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT),
  uint8(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8),
  int8(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8),
  uint16(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16),
  int16(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16),
  int32(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32),
  int64(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64),
  string(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING),
  bool(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL),
  float16(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16),
  float64(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE),
  uint32(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32),
  uint64(b.ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64),
  other(-1);

  const OrtElementType(this.native);

  final int native;

  static OrtElementType fromNative(int code) => values.firstWhere(
    (t) => t.native == code,
    orElse: () => OrtElementType.other,
  );
}

/// A tensor `OrtValue`.
///
/// Buffer ownership (`.claude/wp2/NOTES.md` D2.3): the `from*` constructors
/// copy the Dart data into a `malloc`ed buffer (not `calloc`: the copy
/// overwrites every byte, zero-filling an 8 MB frame first would be waste)
/// and hand that to `CreateTensorWithDataAsOrtValue`, which does not copy;
/// the buffer lives exactly as long as the value and is freed by [dispose].
/// Readers copy out.
/// Values returned by [OrtSession.run] are ORT-allocated; [dispose] releases
/// them. No finalizer: ownership is explicit and deterministic, which is what
/// an inference loop wants.
class OrtValue {
  OrtValue._(this._runtime, this._value, this._buffer);

  /// Wraps [data] with [shape] (row-major, every dimension >= 1).
  factory OrtValue.fromFloat32(
    OrtRuntime runtime,
    Float32List data,
    List<int> shape,
  ) => _create(
    runtime,
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    data.length,
    shape,
    OrtElementType.float32,
  );

  factory OrtValue.fromUint8(
    OrtRuntime runtime,
    Uint8List data,
    List<int> shape,
  ) => _create(runtime, data, data.length, shape, OrtElementType.uint8);

  factory OrtValue.fromInt64(
    OrtRuntime runtime,
    Int64List data,
    List<int> shape,
  ) => _create(
    runtime,
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    data.length,
    shape,
    OrtElementType.int64,
  );

  static OrtValue _create(
    OrtRuntime runtime,
    Uint8List bytes,
    int elementCount,
    List<int> shape,
    OrtElementType type,
  ) {
    final api = runtime._checkedApi;
    if (shape.any((d) => d < 1)) {
      throw ArgumentError.value(shape, 'shape', 'every dimension must be >= 1');
    }
    final expected = shape.fold<int>(1, (n, d) => n * d);
    if (expected != elementCount) {
      throw ArgumentError.value(
        shape,
        'shape',
        'has $expected elements, data has $elementCount',
      );
    }
    final buffer = malloc<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    final dims = calloc<Int64>(shape.length);
    final out = calloc<Pointer<b.OrtValue>>();
    try {
      for (var i = 0; i < shape.length; i++) {
        dims[i] = shape[i];
      }
      api.check(
        api.createTensorWithDataAsOrtValue(
          runtime._cpuMemoryInfo,
          buffer.cast(),
          bytes.length,
          dims,
          shape.length,
          type.native,
          out,
        ),
      );
      return OrtValue._(runtime, out.value, buffer);
    } on OrtException {
      malloc.free(buffer);
      rethrow;
    } finally {
      calloc.free(out);
      calloc.free(dims);
    }
  }

  final OrtRuntime _runtime;
  Pointer<b.OrtValue> _value;
  Pointer<Uint8>? _buffer;
  bool _disposed = false;

  Pointer<b.OrtValue> get _checked {
    if (_disposed) {
      throw StateError('OrtValue has been disposed');
    }
    return _value;
  }

  /// The tensor's dimensions.
  List<int> get shape => _withShapeInfo((api, info) {
    final count = calloc<Size>();
    try {
      api.check(api.getDimensionsCount(info, count));
      final dims = calloc<Int64>(count.value);
      try {
        api.check(api.getDimensions(info, dims, count.value));
        return List<int>.generate(count.value, (i) => dims[i]);
      } finally {
        calloc.free(dims);
      }
    } finally {
      calloc.free(count);
    }
  });

  OrtElementType get elementType => _withShapeInfo((api, info) {
    final type = calloc<UnsignedInt>();
    try {
      api.check(api.getTensorElementType(info, type));
      return OrtElementType.fromNative(type.value);
    } finally {
      calloc.free(type);
    }
  });

  int get _elementCount => _withShapeInfo((api, info) {
    final count = calloc<Size>();
    try {
      api.check(api.getTensorShapeElementCount(info, count));
      return count.value;
    } finally {
      calloc.free(count);
    }
  });

  /// A copy of the elements; throws [StateError] unless [elementType] is
  /// [OrtElementType.float32].
  Float32List toFloat32List() => Float32List.fromList(
    _data<Float>(OrtElementType.float32).asTypedList(_elementCount),
  );

  /// A copy of [count] float32 elements starting at element [offset]
  /// (default: everything from [offset] on), bounds-checked against the
  /// tensor's element count; for reading one row of a large output without
  /// copying the whole tensor. Throws [RangeError] when the window does not
  /// fit, [StateError] unless [elementType] is [OrtElementType.float32].
  Float32List readFloat32({int offset = 0, int? count}) {
    final total = _elementCount;
    final n = count ?? total - offset;
    if (offset < 0 || n < 0 || offset + n > total) {
      throw RangeError(
        'window [$offset, ${offset + n}) is outside the tensor\'s $total '
        'elements',
      );
    }
    final data = _data<Float>(OrtElementType.float32);
    return Float32List.fromList((data + offset).asTypedList(n));
  }

  Uint8List toUint8List() => Uint8List.fromList(
    _data<Uint8>(OrtElementType.uint8).asTypedList(_elementCount),
  );

  Int64List toInt64List() => Int64List.fromList(
    _data<Int64>(OrtElementType.int64).asTypedList(_elementCount),
  );

  Pointer<T> _data<T extends NativeType>(OrtElementType expected) {
    final value = _checked;
    final actual = elementType;
    if (actual != expected) {
      throw StateError('tensor holds ${actual.name}, not ${expected.name}');
    }
    final api = _runtime._checkedApi;
    final out = calloc<Pointer<Void>>();
    try {
      api.check(api.getTensorMutableData(value, out));
      return out.value.cast<T>();
    } finally {
      calloc.free(out);
    }
  }

  R _withShapeInfo<R>(
    R Function(_OrtApi api, Pointer<b.OrtTensorTypeAndShapeInfo> info) body,
  ) {
    final value = _checked;
    final api = _runtime._checkedApi;
    final out = calloc<Pointer<b.OrtTensorTypeAndShapeInfo>>();
    try {
      api.check(api.getTensorTypeAndShape(value, out));
      try {
        return body(api, out.value);
      } finally {
        api.releaseTensorTypeAndShapeInfo(out.value);
      }
    } finally {
      calloc.free(out);
    }
  }

  /// Releases the value and, for a `from*` value, its buffer. Safe to call
  /// twice.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _runtime._api.releaseValue(_value);
    _value = nullptr;
    final buffer = _buffer;
    if (buffer != null) {
      malloc.free(buffer);
      _buffer = null;
    }
  }
}
