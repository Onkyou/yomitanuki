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

## Task 2b: the ORT adapters (`app/lib/data/services/ort`, branch `wp2b-ort-adapters`)

Written 2026-10-14. Scope: `OrtTextDetector` and `OrtOcrEngine` over the WP2a binding and the
WP0b graphs, the worker isolate they run in, the model files on device, the goldens in the gate.
No view code, no `main.dart` wiring (WP4 owns it; the signatures are at the end). The model
assets in this worktree were copied from the parent checkout's `app/assets/models/` (built by
WP0b's `make models`) and every sha256 verified against `manifest.json` and the goldens'
`models_sha256` before the first test ran; `make models` in the worktree then only created
`wp0/.venv` and reported the manifest up to date.

### Decisions

- **D2.13 One worker isolate per adapter; a request/response protocol by id.**
  `OrtInferenceWorker` (`ort_inference_worker.dart`) spawns one long-lived isolate that opens
  the `OrtRuntime`, loads the graphs it is configured for (`WorkerGraphs.detector`: the
  detector session; `WorkerGraphs.ocr`: encoder + decoder + `vocab.txt`) and serves
  `detect(frame, confThreshold)` → `Float32List` (the `[N,5]` rows, flattened),
  `recognise(crop, maxLength)` → `RecognisedCrop` (ids, text, encoder/decoder/total durations)
  and `dispose`. `OrtTextDetector` and `OrtOcrEngine` each own one worker rather than sharing a
  three-session one: the brief allowed either, and separate workers mean a 1 Hz detection pass
  never queues behind an OCR pass (ORT `run` is synchronous and blocks its isolate), either
  adapter can be disposed alone, and WP4 can create them in any order. Cost: two `OrtRuntime`s
  (cheap, D2.11) and two isolates. Every request carries an id from a counter; the worker
  processes its inbox in order, so answers arrive in order, but the completer is looked up by
  id, never by position, and an answer whose id is no longer pending (the adapter was disposed
  meanwhile) is dropped. `dispose()` fails every pending request with `InferenceError('disposed
  while the request was in flight')` first, then sends the dispose message; the worker finishes
  the run it is in, releases sessions and runtime, closes its inbox and exits; the adapter waits
  for the exit (`onExit` port, 10 s timeout → `kill`). Each `ReceivePort` is listened to exactly
  once: cancelling the subscription closes the port (`_controller.onCancel = close` in the VM's
  `isolate_patch.dart`), which the first draft of `spawn` got wrong.
- **D2.14 Errors cross the boundary as the exception itself, never as a dead isolate.** Inside
  the worker every request handler is wrapped: an `OrtException` (plain data: enum, int, String)
  and an `InferenceError` are sent back as they are, with the stack trace as a string; any other
  throwable becomes `InferenceError('unexpected failure in the inference isolate', cause: '$e')`.
  A load failure before the worker is ready is rethrown from `spawn` (a missing model file is
  ORT's `OrtException(noSuchFile)`); an isolate that dies anyway (`onError`/`onExit`) fails every
  pending request with an `InferenceError`. `InferenceError` is named after what it reports but
  `implements Exception` (the caller handles it: show the failure, retry the next frame); misuse
  stays a `StateError` (`detect` after `dispose`), bad constructor arguments an `ArgumentError`
  (`confThreshold` outside `[0,1]`, `maxLength < 2`), per D2.9. Frame geometry that does not add
  up (`bytesPerRow < width*4`, too few bytes) is checked in the worker and is an
  `InferenceError`, not an `ArgumentError`: a camera plane is runtime data.
- **D2.15 Transfer strategy: `TransferableTypedData`, repack in the worker.** A frame crosses
  as `TransferableTypedData.fromList([image.bytes])` plus width/height/bytesPerRow: one copy
  into the transfer buffer on the UI isolate (unavoidable: the plugin owns its plane), none on
  `materialize()`. The worker repacks row-padded buffers to the tight `[1,H,W,4]` the graphs
  want (one more copy only when `bytesPerRow != width*4`), and `OrtValue.fromUint8` copies once
  more into its `malloc` buffer (D2.3). Budget per 1080p detection: 2 copies of 8.3 MB, 3 when
  the stream pads rows. The zero-copy route (D2.3's `CreateTensorWithDataAsOrtValue` over the
  plugin's pointer) stays unused until the on-device timing says otherwise. Crops arrive
  already tight from `BgraImage.crop()`; the OCR worker never sees the whole frame.
- **D2.16 Model files on device: `ModelAssets.prepare`, stamped by `manifest.json`.** ORT opens
  files, so the four bundle assets (`assets/models/{detector.onnx,ocr_encoder.onnx,
  ocr_decoder.onnx,vocab.txt}`, declared in `pubspec.yaml`, directory kept by a `.gitkeep` that
  `.gitignore` now allows) are copied into an injected directory (`ModelAssets.defaultDirectory()`
  = `<application support>/models` via `path_provider`; application support is not backed up
  and not user-visible). Each copy is written to `<name>.partial`, hashed (`crypto` sha256, in a
  helper isolate reading the file, so 87 MB never blocks the UI isolate) against the bundle
  manifest's sha256 and renamed; a mismatch throws `ModelAssetsException` naming the file. The
  bundle's `manifest.json` is written last as the stamp. On the next start the stamp is compared
  with the bundle manifest (sha256 per file) and every file checked for existence and size; any
  difference recopies everything (one `make models` changes all three graphs anyway). The
  seam: an `AssetBundle` and a `Directory`, tested with `test/fakes/fake_asset_bundle.dart`
  (hand-written) and a temp directory; `ModelAssets.inDirectory(dir)` is what the tests use on
  `assets/models/` directly and what a future "models from the Files app" path would use.
- **D2.17 Detector defaults: `confThreshold` 0.2 (D0.11), CoreML on, cache beside the models.**
  `OrtTextDetector.create(assets:, confThreshold: 0.2, coreMl: true, coreMlCacheDirectory:,
  ortLibraryPath:)`: the threshold is validated to `[0,1]` (the graph clips, but a negative
  value would be a silent "everything", D0.11) and fed as the `conf_threshold` input of every
  run; `coreMl: true` appends the provider with exactly D0.10 + D0b.6 (`CoreMlOptions` defaults:
  `NeuralNetwork`, `CPUAndNeuralEngine`, `RequireStaticInputShapes=1`) and
  `ModelCacheDirectory` = `coreMlCacheDirectory ?? assets.coreMlCacheDirectory`
  (`<models dir>/coreml_cache`, writable because the models dir is). Boxes are clamped to the
  frame (D0b.8: the graph does not clip), order and scores kept as the graph gives them (score
  descending); `N = 0` is an empty list without reading the `[0,5]` tensor's data pointer.
  OCR: `OrtOcrEngine.create(assets:, maxLength: 300, ortLibraryPath:)`, CPU provider only
  (D0b.6), `recognise` answers the port with `OcrResult(text, elapsed = worker total)`;
  `recogniseDetailed` adds ids and per-stage timings for the goldens and WP2 task 1.
- **D2.18 Test policy: CPU provider for exactness, CoreML for "within one block" and the
  zero-detection case.** The golden tests (`test/data/services/ort/ort_text_detector_test.dart`,
  `ort_ocr_engine_test.dart`) go through the real adapters, i.e. the worker isolate and the
  dylib from `make ort-macos`. CPU provider: every `ocr/*` fixture gives the recorded ids and
  text exactly (the two `.bgra` fixtures are asserted to be row-padded, so the repack path is
  the one under test), every `detector/*` page the recorded blocks within the JSON tolerance
  capped at ±4 px / ±0.05 (`check_goldens.py`'s ceiling, reimplemented in
  `test/support/goldens.dart` with the same one-to-one matching). CoreML provider, same pages:
  threshold-edge boxes may flip under ANE fp16 (D0b.6), so the assertion is "at most one
  golden block unmatched, at most one unexpected block, count within one"; on this M2 all four
  pages match exactly anyway. A blank 1080x1920 frame on CoreML must give an empty list and
  not throw (the D0b.6 failure mode). Every golden test first checks the golden's
  `models_sha256` against `assets/models/manifest.json` (the build's own record; the files
  themselves are hashed by `ModelAssets.prepare` at copy time, and hashing 145 MB per test run
  would be a test of the disk, not of the port).
- **D2.19 The goldens are in the gate, with their own mutation proof.** `make gate-test` now
  depends on `models` (and `ort-macos`, `deps`); ci.yml gets `astral-sh/setup-uv@v6` and a
  `make models` step before `flutter test`, line for line with the Makefile. `tool/gate_proof.sh`
  has a fourth step: it refuses to start if `app/test/goldens/ocr/v_single.json` has local
  modifications, appends ` corrupted` to that golden's recorded text in place (sed), asserts
  `make gate-test` goes red with `v_single` and `Some tests failed` in the output (two tests
  name it: the adapter golden and the pure `postProcess(detokenise(ids))` check), restores with
  `git checkout -- <file>` (also from the EXIT trap), and the existing final check proves
  `git status` unchanged. **What the first CI run must verify**, because none of it has run on
  a GitHub runner yet: that `setup-uv` provides `uv` and that `uv venv --python 3.14` resolves
  (Python 3.14 is downloaded by uv if the runner lacks it); that `make models` can download the
  manga-ocr weights from the Hugging Face hub (`optimum-cli export onnx -m
  kha-white/manga-ocr-base`, unauthenticated) and the comic-text-detector weights that
  `mokuro.cache` fetches (GitHub release); that the export runs within the job's 45 min
  (≈3 min on the M2, the runners are slower; raise `timeout-minutes` if needed); and that the
  CoreML provider compiles on a runner without an ANE (`CPUAndNeuralEngine` falls back to the
  CPU inside CoreML; the ort_ffi package tests already append the provider but had not run on
  CI before the WP2a merge's first gate either). The venv and the Hugging Face cache are worth
  caching between runs once this is green.
- **D2.20 Post-processing is a parity port of `manga_ocr.ocr.post_process` + jaconv 0.5.0.**
  `manga_ocr_text.dart`: `MangaOcrVocab.parse` (one token per line, index = id, trailing
  newline dropped), `detokenise` (skip ids 0–4 and `<unused…>`, concatenate; an id outside the
  vocabulary is an `ArgumentError`), `postProcess` (Python's `str.split()` whitespace set, which
  is not Dart's `\s`: NEL U+0085 and U+001C–U+001F are whitespace, U+FEFF is not; `…`→`...`;
  `[・.]{2,}`→ the same number of `.`; then `halfToFullWidth` = `jaconv.h2z(ascii=True,
  digit=True, kana=True)`: the 25 dakuten/handakuten merges first in jaconv's order, printable
  ASCII `+0xFEE0`, space → U+3000, the half-width katakana block U+FF61–U+FF9D by table, the
  lone marks U+FF9E/U+FF9F untouched). The expected table in the test was produced by running
  the pinned venv's jaconv over the cases, so it is parity, not opinion; the pinned jaconv
  (0.5.0) maps `"`/`'`/`\``/`\\` to U+FF02/U+FF07/U+FF40/U+FF3C, older jaconv used curly
  quotes and `￥`, so a lock-file bump of jaconv must re-run the table.
- **D2.21 Test support decodes PNG itself.** `test/support/png.dart` (8-bit grey/RGB/RGBA,
  non-interlaced, any filter, concatenated IDAT, `dart:io` zlib) rather than `dart:ui`'s codec:
  the goldens are exact pixels and the engine's colour management is not part of the contract.
  It has its own test (a 4x5 fixture whose rows use filter types 0–4, expected bytes from
  Pillow).
- **D2.22 Measured on this Mac (Apple M2, ORT 1.31 dylib, default threads, medians of 5 warm
  runs, wall clock from the UI isolate through the worker, i.e. transfer + tensor copy + run +
  reply; `ORT_TIMING=5 flutter test --concurrency=1 test/data/services/ort/ort_*_test.dart`
  reprints them). `--concurrency=1` matters: the first measurement ran the detector and the OCR
  suite in two test isolates at once and the CPU-provider numbers doubled (336 ms/page, 110
  ms/crop); the review re-measured alone and so does this table:**

  | | median |
  |---|---|
  | detector, CPU provider, per golden page (1000x1414, 1414x1000, 1080x1920, 1000x1414 colour) | 159 / 157 / 161 / 156 ms |
  | detector, CoreML provider (D0.10 + D0b.6), same pages | 31.7 / 31.8 / 36.0 / 32.1 ms |
  | OCR, CPU provider, per golden crop (14 crops, 5–18 ids) | 56–84 ms, ≈68 ms typical (encoder ≈ 45 ms + 2–3 ms per decoder step + transfer/copies) |

  The CoreML page number (32 ms incl. the in-graph letterbox of a 1.4 MP page) is 3x better
  than D0b.6's 106 ms, which was on 12 MP photos; the CPU number is in line with D0.7's 151 ms
  for the net alone. CoreML compile on first session creation: ≈2 s, then served from the
  cache directory. None of this transfers to the phone (C9); it bounds the Mac gate's cost (the
  app test run is ≈10 s with both providers).
- **D2.23 What the first on-device run (WP2 task 1) must check, in this order.**
  (1) `OrtRuntime.process()` finds `OrtGetApiBase` (or the `ort_ffi_get_api_base` fallback) in
  the release build: it has never executed on iOS (D2.5, D2.7). (2) `ModelAssets.prepare`:
  time of the first copy (145 MB + sha256) and that the stamp skips it on the second launch;
  watch the ORT log for a `ModelCacheDirectory` ERROR (cache silently disabled, D2.8).
  (3) CoreML partition count for the detector in ORT's warning-level log: WP0b saw 7 partitions
  with 257/296 nodes on CoreML on macOS; a markedly different count on iOS means a different
  fallback set. (4) Per-stage timing per PLAN WP2 task 1 at the 1080p stream preset: frame
  copy into `TransferableTypedData`, repack (if the plane is padded), `OrtValue` copy, `run`,
  reply, box mapping, and for OCR `RecognisedCrop.encoder/decoder/total` vs `OcrResult.elapsed`
  measured on the UI isolate; targets per D0.13: one detection pass well under a second, one
  OCR pass about a second; CPU-only detector (`coreMl: false`) as the comparison and the
  fallback. (5) Memory (C4) with both workers resident. (6) A frame with zero detections on
  the device's CoreML build (D0b.6), e.g. the lens covered.

### Wiring (done on this branch after the main merge: `app/lib/main.dart`, D2.25)

`AppDependencies.production()` creates `LazyInference.production()` and passes its
`detector` and `ocr` ports; nothing else in the app knows the ORT adapters exist.

```dart
final inference = LazyInference.production();   // == production(coreMl: true, confThreshold: 0.2)
detector: inference.detector,                   // TextDetector; the real adapter on first detect
ocr: inference.ocr,                             // OcrEngine; the real adapter on first recognise
```

`LazyInference.production()` is `ModelAssets.prepare(bundle: rootBundle, directory: await
ModelAssets.defaultDirectory())` once, then `OrtTextDetector.create(assets:, confThreshold:,
coreMl:)` and `OrtOcrEngine.create(assets:)` on their first use; the constructor
`LazyInference({prepare, detector, ocr})` takes the three steps as functions (the tests pass
fakes). Nothing touches the platform at construction, so `main_test` still builds
`production()`.

Exact signatures:

```dart
factory LazyInference.production({AssetBundle? bundle, bool coreMl = true, double confThreshold = 0.2});
LazyInference({required PrepareModels prepare, required CreateDetector detector, required CreateOcr ocr});
TextDetector get detector; OcrEngine get ocr; Future<void> dispose();   // disposes what was created
static Future<OrtTextDetector> OrtTextDetector.create({
  required ModelAssets assets,
  double confThreshold = 0.2,      // [0, 1], ArgumentError otherwise
  bool coreMl = true,              // false: CPU provider (the exactness tests)
  String? coreMlCacheDirectory,    // default assets.coreMlCacheDirectory
  String? ortLibraryPath,          // null: OrtRuntime.process()
});
static Future<OrtOcrEngine> OrtOcrEngine.create({
  required ModelAssets assets,
  int maxLength = 300,             // >= 2
  String? ortLibraryPath,
});
Future<List<TextBlock>> OrtTextDetector.detect(BgraImage image);   // port
Future<OcrResult> OrtOcrEngine.recognise(BgraImage crop);          // port
Future<RecognisedCrop> OrtOcrEngine.recogniseDetailed(BgraImage crop); // ids + timings
Future<void> dispose();                                            // both; idempotent
static Future<ModelAssets> ModelAssets.prepare({required AssetBundle bundle, required Directory directory});
static Future<Directory> ModelAssets.defaultDirectory();           // <app support>/models
ModelAssets.inDirectory(Directory directory);                      // files already there
```

Errors the reader sees through the lazy ports (D2.25): `ModelsUnavailableError(reason)` (the
bundle lacks or mis-hashes a model: a build error, "Rebuild the app with `make models`"),
`InferenceFailedError(reason)` (ORT's own failure, a frame whose geometry does not add up, the
worker gone: "Text recognition failed. Please try again."), `StateError` (use after dispose,
unmapped on purpose: a programming error). Below the lazy layer the adapters throw
`OrtException`, `InferenceError`, `ModelAssetsException`, `ArgumentError` as before. Nothing is
logged by the adapters; ORT itself logs warnings and errors to stderr (D2.8's note), which is
where the partition count and a cache-directory failure show up.

### What will bite WP4 / the first device run

- **The first detection pays for everything**: the 145 MB copy out of the bundle plus sha256
  (seconds on a phone), two isolate spawns, the session loads and the CoreML compile (≈2 s on
  the M2, cached afterwards). The reader shows "scanning" meanwhile; a splash that calls
  `detector.detect` on a blank frame would move the wait to launch if that is preferred.
- `detect` and `recognise` are serialised per adapter (one isolate each): a `detect` issued
  while one is running waits. Sample at ~1 Hz (D0.13) and skip a frame when the previous
  `detect` has not answered; do not queue frames.
- `OcrResult.elapsed` is the worker's time; the UI-isolate round trip adds the transfer copy.
- `BgraImage.crop()` on the UI isolate is a pixel loop over the crop only (small); keep the 8 %
  margin (D0.6) there, the OCR adapter does not add it.
- The CoreML cache directory is created by ORT under the models directory; deleting the
  models directory (e.g. a future "reset" setting) deletes the cache too, which is fine.
- `flutter test` needs `make models` and `make ort-macos` first (`make gate-test` does both);
  a fresh clone without them fails the golden tests with "run `make models`".

### Review 2026-10-14 (two adversarial reviews of the diff; findings applied)

- **D2.24 Corrections.** (1) Two concurrent `ModelAssets.prepare` calls on one directory raced
  on the shared `<name>.partial` and escaped as an untyped `PathNotFoundException`: the
  in-flight `Future<ModelAssets>` is now memoised per absolute directory path until it
  completes (a `whenComplete` whose callback must not *return* the removed future, or it waits
  on itself), each copy goes to `<name>.<pid>.<seq>.partial` before the atomic rename, and a
  `FileSystemException` anywhere in the copy is rethrown as `ModelAssetsException`; the test
  runs three `prepare`s at once and expects one copy and no leftover partials. (2) The proof's
  fourth step accepted `v_single` as evidence, which the pure `postProcess(detokenise(ids))`
  test also prints, so a gate with every real-ORT golden test skipped would still have passed
  the proof: the evidence is now the adapter test's full name, `v_single.png reads the recorded
  ids and text`, and the EXIT trap reports a failed restore. (3) `OrtValue.readFloat32({offset,
  count})` (ort_ffi, bounds-checked, tested) replaces copying the whole `[1,L,6144]` logits per
  decoder step. (4) The detector handler creates the `conf_threshold` value inside the `try`,
  so a throwing `OrtValue.fromFloat32` cannot leak the 8 MB image value; `_send` builds the
  request before registering the completer. (5) `GreedyDecoder` throws `InferenceError` on a
  NaN logit (numpy's argmax would return the first NaN's index, Dart's `>` would skip it;
  either way the graph diverged). (6) D2.22 re-measured with `--concurrency=1`. (7) `make
  models` has a `check-uv` precondition with a message naming `brew install uv` and the CI
  action.
- **D2.25 Lazy wiring and the error boundary.** `LazyInference` (`lazy_inference.dart`) follows
  `LazyDictionary`: one `_Once` per step (prepare, detector, OCR), shared while in flight,
  forgotten on failure so the next call retries, `dispose` only of what was created. The
  adapter errors are mapped to domain errors **in the lazy wrappers**, not by moving
  `InferenceError` into `domain/`: `reader_errors.dart` imports only `domain/`, the domain must
  not know ONNX Runtime (`OrtException` is an `ort_ffi` type and would have needed the same
  treatment), and one boundary that maps is the pattern `LazyDictionary` already set for
  `DictionaryAssetError` → `DictionaryUnavailableError`. `ModelAssetsException` →
  `ModelsUnavailableError`, `OrtException`/`InferenceError` → `InferenceFailedError`, both new
  in `lib/domain/errors.dart` with sentences in `describeReaderError`. The `Unavailable…`
  stand-ins file is deleted (every port has an adapter now); `NotWiredError` stays because the
  reader tests use it as the generic adapter error.
