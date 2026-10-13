/// ONNX Runtime for Yomitanuki over `dart:ffi` (WP2 task 0).
///
/// One [OrtRuntime] per isolate that runs inference, [OrtSessionOptions] with
/// the CoreML execution provider options of WP0 D0.10, [OrtSession] loaded
/// from a file, [OrtValue] tensors in and out. Every ORT status becomes an
/// [OrtException]; every object has an idempotent `dispose()`.
///
/// Decisions: `.claude/wp2/NOTES.md`.
library;

export 'src/ort.dart'
    show
        OrtElementType,
        OrtErrorCode,
        OrtException,
        OrtGraphOptimizationLevel,
        OrtRuntime,
        OrtSession,
        OrtSessionOptions,
        OrtTensorInfo,
        OrtValue;
