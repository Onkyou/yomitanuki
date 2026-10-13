# WP2 notes

Decisions are numbered D2.n and stay binding until explicitly reversed (PLAN.md §4.3).
Task 0 (the ORT binding, branch `wp2a-ort-binding`) is below; later tasks append.

## Task 0: the ONNX Runtime binding (`app/packages/ort_ffi`)

Written 2026-10-13. Scope: a typed Dart API over the ONNX Runtime C API via `dart:ffi`,
the macOS runtime for `flutter test`, the iOS pod, and the gate changes the first native
dependency brings. No adapters for the domain ports (that is WP2b), no view code.

### Decisions

- **D2.1 Plugin layout.** `app/packages/ort_ffi` is a Flutter FFI plugin (`ffiPlugin: true`,
  iOS only), a path dependency of the app. No platform channel, no Swift, no native assets
  (`dart-setup-ffi-assets` is deliberately not used; the runtime is linked by CocoaPods).
  Public API, all from `package:ort_ffi/ort_ffi.dart`: `OrtRuntime`, `OrtSessionOptions`,
  `OrtGraphOptimizationLevel`, `CoreMlOptions` (+ `CoreMlModelFormat`, `CoreMlComputeUnits`),
  `OrtSession`, `OrtTensorInfo`, `OrtValue`, `OrtElementType`, `OrtException`, `OrtErrorCode`.
  Internally one library in parts (`lib/src/ort.dart`) so the parts share the library-private
  `_OrtApi` without a package-visible accessor on the public classes.
- **D2.2 Bindings are generated, filtered, committed, excluded from analysis, formatted.**
  `tool/ffigen.dart` (ffigen 23, programmatic API; the YAML form is legacy) reads the header of
  the fetched release (`tool/ort/include/onnxruntime_c_api.h`, D2.6) and includes exactly
  `OrtGetApiBase`, the structs `OrtApiBase` and `OrtApi`, the enums the wrapper reads (as
  `int` constants) and `ORT_API_VERSION`; everything else arrives only as a transitive
  dependency. Output `lib/src/bindings/onnxruntime_c_api.g.dart` (9.3k lines) is excluded
  by the package's `analysis_options.yaml` (strict modes fail on generated code,
  `.claude/wp1/NOTES.md`) and formatted by `make ffigen`, because `gate-format` covers the
  whole tree. It lives under `lib/src/bindings/` rather than the `dart-use-ffigen` skill's
  `lib/src/third_party/`: the task brief named that path, and the directory holds only
  generated code, so one name for one thing. The header is not committed under `third_party/` as `dart-use-ffigen` prefers:
  the one pinned archive is the single source of both the dylib and the header, so the
  bindings cannot be generated from a different release than the one linked.
- **D2.3 Buffer ownership: malloc copies, explicit dispose, no finalizer.** `OrtValue.from*`
  copies the Dart list into a `malloc`ed buffer (`package:ffi` `malloc`, not `calloc`: the
  copy overwrites every byte, so zero-filling an 8 MB frame first would be pure cost; the
  review caught the code saying `calloc` while the notes said malloc) and hands that to
  `CreateTensorWithDataAsOrtValue` (which does not copy); the buffer lives exactly as long as
  the value and `dispose()` frees it. The small scratch allocations (out-pointers, dims,
  name arrays) stay `calloc`. Readers (`toFloat32List` etc.) copy out. Outputs of
  `run` are ORT-allocated and released by `dispose()`. No `Finalizer`/`NativeFinalizer`:
  ownership in an inference loop should be deterministic, and the adapters (WP2b) own values
  in `try`/`finally`. Cost: one extra copy per input tensor (see "What will bite").
- **D2.4 API version 30 is requested, from a header that says 31.** The pod is 1.30.0
  (`onnxruntime-c` 1.31.0 is not on CocoaPods as of 2026-10-13; newest is 1.30.0, published
  2026-09-10, its header says `ORT_API_VERSION 30`), the macOS dylib is 1.31.0. The rule is
  in the implementation, `onnxruntime/core/session/onnxruntime_c_api.cc`: `OrtApis::GetApi`
  returns the one full struct (`ort_api_1_to_29` by name) for every `1 <= version <=
  ORT_API_VERSION` and `nullptr` otherwise; the comment above it ("NEVER remove or rearrange
  the members in this structure unless a new version is being created") is enforced by
  `static_assert(offsetof(OrtApi, ...) / sizeof(void*) == N)` for each released version's
  last member. Checked against both headers: 1.30's `OrtApi` (426 members) is an exact prefix
  of 1.31's (428), so `OrtRuntime.apiVersion = 30` is valid against both and nothing this
  package calls was added after 30. When the pod catches up, raise the constant and the pin
  together.
- **D2.5 How the library is located.** macOS: `OrtRuntime.open(path)` with an explicit path;
  the tests take `ORT_DYLIB` or default to `tool/ort/lib/libonnxruntime.1.31.0.dylib`
  relative to the package and fail with "run `make ort-macos`" otherwise. iOS:
  `OrtRuntime.process()` (`DynamicLibrary.process()`), because `onnxruntime-c` is a static
  xcframework: CocoaPods refuses a dynamic framework with a static transitive dependency, so
  `ort_ffi` is `static_framework = true` and everything lands in the app binary.
  `ios/Classes/ort_ffi.m` keeps it reachable: an Objective-C class (so `-ObjC` forces the
  object file in) plus `ort_ffi_get_api_base`, which references `OrtGetApiBase` and thereby
  drags the whole runtime in. Dart looks up `OrtGetApiBase` and falls back to
  `ort_ffi_get_api_base`. Runner's Profile/Release `STRIP_STYLE` is `non-global`, Flutter's
  documented setting so a by-name lookup survives stripping.
- **D2.6 The macOS artefact.** `onnxruntime-osx-arm64-1.31.0.tgz` from the GitHub release
  (no universal2 archive exists for 1.31.0), sha256
  `1031b36dd3bdaa8d976a6130d9cf2a05e9be320b93ae804f8427b91dc3432afc`, pinned in the Makefile
  only; `make ort-macos` downloads into its own directory, verifies, extracts, copies out the
  dylib, `include/` and `LICENSE` to the ignored `app/packages/ort_ffi/tool/ort/`, and deletes
  the download. ci.yml calls `make ort-macos` rather than restating the hash. The dylib links
  CoreML, i.e. the CoreML EP is in the macOS binary.
- **D2.7 Gate.** `gate-test` depends on `ort-macos` and runs `flutter test` in the app and in
  the package (two pub packages). New `gate-build-ios`: `flutter build ios --simulator
  --no-codesign` (debug) and `flutter build ios --release --no-codesign` (unsigned device
  build: links and strips, needs no provisioning, cannot be installed), each followed by
  `nm` over `Runner.app/Runner*` showing `T _OrtGetApiBase`, so a build that silently
  dropped the static library, or a release strip that removed the symbol, is red. `make gate` = format, analyze, test,
  proof, build-ios; ci.yml mirrors step for step (`LANG=en_US.UTF-8` on the build, CI timeout
  30 -> 45 min). The proof script is unchanged: its failing-test fixture lands in `app/test`,
  which is the first of the two test runs.
- **D2.8 CoreML provider options = D0.10 + `RequireStaticInputShapes=1`.** `appendCoreML`
  uses the string-keyed `SessionOptionsAppendExecutionProvider("CoreML", keys, values)` with
  `ModelFormat=NeuralNetwork`, `MLComputeUnits=CPUAndNeuralEngine`, the caller's
  `ModelCacheDirectory` (need not exist: ORT creates it; if it cannot, ORT logs an ERROR,
  silently disables caching and recompiles for every session) and
  `RequireStaticInputShapes=1` (WP0b: without it
  ORT 1.31 places the detector's post-NMS Gather with a dynamic `[M]` shape on CoreML and
  every run with zero detections fails with "runtime shape {0} has zero elements"). All four
  are fields of `CoreMlOptions`; the first three have no other sensible value for this app,
  the last can be switched off per session.
- **D2.9 Errors.** Every ORT status goes through `_OrtApi.check`, which releases the status
  and throws `OrtException(code, message)` with ORT's own text and the numeric code
  (`OrtErrorCode.unknown` keeps the number for codes a newer runtime may add). A library that
  cannot be loaded or an API version the runtime does not provide is also an `OrtException`.
  Programming errors are Dart errors: `StateError` for use after dispose or reading a tensor
  as the wrong type, `ArgumentError` for a shape that does not match the data.
- **D2.10 iOS deployment target 15.1** (Podfile and Runner.xcodeproj), the floor of
  `onnxruntime-c` 1.30.0; it was 15.0.
- **D2.11 Isolates: the worker owns everything.** `OrtRuntime`, sessions and values hold
  pointers and must not cross isolates; the test pattern (and the one WP2b uses) is
  `Isolate.run` opening the runtime, loading, running, disposing, returning plain typed data.
  ORT shares one environment per process underneath, so a runtime per isolate is cheap.
- **D2.12 Outputs never alias inputs; `run` rejects duplicate output names.** Review finding:
  for a graph whose output IS a graph input (no node between them), `Run` hands the input
  `OrtValue` back without allocating, so the fetched value shares the caller's `malloc`ed
  buffer and disposing the input first is a use-after-free (probed with the 65-byte
  `passthrough.onnx` fixture). `OrtSession.fromFile` now throws
  `OrtException(invalidGraph)` when input and output names intersect; no model this app
  ships does that. A duplicate name in `outputNames` would produce two `OrtValue`s under one
  key and leak one; `run` throws `ArgumentError`. Leak-class mutations (a skipped
  `ReleaseStatus`/`AllocatorFree`/`ReleaseValue`, release order) are not black-box testable
  from Dart; the dispose and error paths were reviewed by hand instead.

### What the gate proved

- `flutter build ios --simulator --no-codesign`: green on Xcode 26.0.1 / iPhone simulator
  SDK. `nm -gU Runner.app/Runner.debug.dylib` shows `T _OrtGetApiBase`,
  `T _OrtSessionOptionsAppendExecutionProvider_CoreML` and `T _ort_ffi_get_api_base`. Xcode
  26 builds a debug app's code into `Runner.debug.dylib` beside a 72 kB stub `Runner`; older
  Xcodes (the `macos-15` runner) put it in `Runner`, hence the `Runner*` glob.
- `flutter build ios --release --no-codesign` (unsigned device build): green, 51 MB
  `Runner.app`; `nm -gU build/ios/iphoneos/Runner.app/Runner` shows `T _OrtGetApiBase` and
  `T _ort_ffi_get_api_base` after Xcode's release strip, i.e. `STRIP_STYLE=non-global`
  keeps the symbol `DynamicLibrary.process()` looks up. The binary is not installable
  (unsigned), so the lookup itself is first exercised on the phone in WP2 task 1.
- `pod install` (with `LANG=en_US.UTF-8`): `onnxruntime-c 1.30.0`, `ort_ffi 0.1.0`.
- On macOS with the CoreML EP appended: the static-shape float32 graph and the uint8 cast
  graph are compiled by CoreML (`ModelCacheDirectory` gets a `<hash>/0_dynamic_nn` model),
  the dynamic-shape graph stays on the CPU under `RequireStaticInputShapes=1`, and the int64
  graph stays on the CPU regardless (CoreML NeuralNetwork has no int64 Add). None of them
  throw; results are identical to the CPU provider.
- 29 package tests: runtime (version, API version, bad path, dispose), session (metadata of
  single- and multi-input graphs, missing file -> `noSuchFile`, wrong input name ->
  `invalidArgument` naming it, missing input, unknown output, dispose), run on float32/uint8/
  int64 with correct values and shapes, values (round trips, copy semantics, shape checks,
  type checks, dispose), CoreML (option map, compile, CPU fallback, dispose), `Isolate.run`.

### What will bite WP2b

- **Tensor copies.** A 1080p BGRA frame is 1920x1080x4 = 8.3 MB. `OrtValue.fromUint8` copies
  it once (Dart -> `malloc`); getting the frame into the worker isolate copies it again unless it
  travels as `TransferableTypedData`; the detector's output comes back through
  `toFloat32List` (small). Budget ~2 copies of 8 MB per detection at ~1 Hz, fine, but the OCR
  crop path should crop in the worker, not copy the whole frame per bubble. If this ever
  matters, `CreateTensorWithDataAsOrtValue` over a `Pointer` the camera plugin already owns is
  the zero-copy route and needs only a new `OrtValue._` entry point.
- **`run` is synchronous** and blocks its isolate for the whole inference; it must never be
  called on the UI isolate (the port docs say so). A long-lived worker isolate with the
  session loaded once is the shape; `Isolate.run` per call would reload the model.
- **`OrtValue.from*` take the runtime as first argument**; values are bound to the isolate
  that made them.
- **CoreML cache directory must be writable**, e.g. a subdirectory of
  `getApplicationSupportDirectory()`; ORT creates it, and if it cannot, it logs an ERROR,
  silently disables caching and recompiles the model for every session (1.8 s on M2 per
  WP0), so watch the log on first device runs.
- **ORT logs to stderr** at warning level (`CreateEnv` with `ORT_LOGGING_LEVEL_WARNING`);
  a missing input is reported by the executing kernel ("Missing Input: x") before the status
  reaches Dart, so the test output shows one `[E:onnxruntime ...]` line by design.
- **Release-build symbol lookup on the phone is the first thing WP2 task 1 verifies.** The
  gate proves the symbol survives the release strip (`nm` on the unsigned device build), not
  that `dlsym` returns it in a running process; `OrtRuntime.process()` has never executed on
  iOS. If `OrtGetApiBase` is missing at run time, the fallback symbol `ort_ffi_get_api_base`
  is tried next; if both are, add an `-exported_symbols_list`.
- **Flutter warns that `ort_ffi` has no Swift Package Manager manifest** and "this will become
  an error in a future version of Flutter". `onnxruntime-c` is CocoaPods-only, so a
  `Package.swift` with a binary target for the xcframework is the eventual answer.
- **`make gate` now takes minutes** (three test runs via the proof, then two Xcode builds) and
  needs the network once (`ort-macos`, 36 MB) and CocoaPods (`pod install` inside
  `flutter build ios`).
- **ffigen prints `No definition found for declaration` warnings** for forward-declared ORT
  structs during `make ffigen`; harmless (they become opaque types).
