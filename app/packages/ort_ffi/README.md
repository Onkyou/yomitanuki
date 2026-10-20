# ort_ffi

ONNX Runtime for Yomitanuki over `dart:ffi`: a small typed Dart layer (`OrtRuntime`,
`OrtSessionOptions` with CoreML options, `OrtSession`, `OrtValue`, `OrtException`) over
bindings that `ffigen` generates from `onnxruntime_c_api.h` (`tool/ffigen.dart`, `make ffigen`).

- **macOS tests** load the 1.31.0 dylib that `make ort-macos` fetches into `tool/ort/`
  (sha256 pinned in the root Makefile); `flutter test` here runs real inference.
- **iOS** links the `onnxruntime-c` 1.30.0 pod statically (`ios/ort_ffi.podspec`) and the
  bindings request API version 30 (`.claude/wp2/NOTES.md` D2.4 explains the skew).
- Objects hold native pointers and never cross isolates; open one runtime per inference isolate.

Decisions and the measured behaviour are in `.claude/wp2/NOTES.md`.
