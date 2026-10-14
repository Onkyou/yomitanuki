# WP4 — capture and reader UI: decision log

Branch `wp4-reader-ui`, written 2026-10-13. Built entirely against the domain ports with fakes
(`app/test/fakes/`), before the real detector/OCR (WP2b), dictionary (WP3) and Anki (WP5)
adapters exist. PLAN.md D10, WP0 D0.11–D0.13 and C7/C12/C14 are not repeated; these are the
choices they left open. Binding until explicitly reversed.

## Decisions

- **D4.1 Sampling is frame-driven and clock-gated in the view model, not a timer.**
  `ReaderViewModel` listens to `FrameSource.frames`; on each frame it compares an injected
  `clock()` with the last sample time and runs `TextDetector.detect` only when
  `detectionInterval` (default 1 s, D0.13) has elapsed, nothing is in flight, and no OCR sheet
  is open. Frames that fail any of those are dropped before any work. The first frame is
  detected at once; the first frame after the sheet closes is detected at once too (the clock
  is reset on dismiss), so the boxes never stay stale for a whole interval. Why not a
  `Timer.periodic`: a timer needs the newest frame retained between ticks (one more 8 MB
  buffer) and ticks with nothing to do while the camera is closed; the frame-driven form costs
  a timestamp compare per dropped frame and its phase error (one frame period, ~33 ms) is
  noise at 1 Hz. The view model never runs inference itself: the adapters behind
  `TextDetector`/`OcrEngine` own their isolates (AGENTS.md). **The "no OCR sheet is open"
  clause and the reset-on-dismiss were reversed by WP6a D6a.1 (2026-10-14): detection
  continues behind the sheet and dismiss touches neither the clock nor the generation.**
- **D4.2 Frame ownership and memory: at most three 1080p buffers alive.** The camera adapter
  emits at most one frame per `emitInterval` (250 ms; D0.13 makes anything faster pointless)
  and converts only the frames it emits, so the per-frame cost on the UI isolate for the other
  ~26 frames/s is the plugin's own channel decode plus one `DateTime` compare. The plugin
  hands a fresh `Uint8List` per `CameraImage`, so the adapter keeps a reference instead of
  copying when no rotation is needed. The view model retains exactly one frame, the one its
  current blocks were detected on (`frame`), and at most one more while a detection is in
  flight; the OCR crop is a packed copy (`BgraImage.crop`) made at tap time from `frame`, which
  is what D0.12 asks for ("the same frame the blocks came from"). Nothing else holds frames.
- **D4.3 Orientation: capture locked to portrait, rotate only a landscape buffer.**
  `PluginCameraSession.initialize` calls `lockCaptureOrientation(portraitUp)`;
  `camera_avfoundation` (0.10.3+1 in the lock, Swift) sets `connection.videoOrientation` on
  its video data output connection (`DefaultCamera.swift`: `lockCaptureOrientation` →
  `updateOrientation`), so on iOS the stream buffer already arrives portrait (1080×1920) and
  `orientForPortrait` passes it through untouched. *(Corrected after review: the first version
  cited `FLTCam.m`, the Objective-C file of the 0.9.x plugin this Mac also had cached.)* A landscape
  buffer (sensor orientation, e.g. a plugin version or platform that does not rotate the
  stream) is rotated 90° clockwise by `rotateCw90`, unit-tested pixel by pixel on a 3×2
  synthetic with padded rows. The direction (clockwise for the back camera, sensor
  orientation 90) is the standard iOS/Android mapping and is **unverified on a device**: if
  boxes ever appear mirrored or upside down on a phone, this is the first place to look.
  `CameraPreviewView` swaps the plugin's landscape `previewSize` to portrait for the same
  reason. The iPhone interface orientation is locked to portrait in `Info.plist` so the
  preview, the frame and the overlay cannot disagree.
- **D4.4 One `FrameMapping` for drawing and hit-testing.** Blocks live in frame pixels; taps
  arrive in preview pixels; `FrameMapping` (uniform scale + centring offset) is the only
  converter. Camera: `cover` (the preview fills the body, matching `CameraPreviewView`'s
  `FittedBox(fit: cover)`); still photo: `contain` (cropping a page edge would hide bubbles).
  Tap targets are at least 44 logical px on each side and the smallest containing box wins, so
  a caption inside a bubble stays tappable. The overlay is a `LayoutBuilder` over the Scaffold
  body (below the app bar), the same box the preview is painted in.
- **D4.5 Photos are decoded by `dart:ui`, which applies EXIF orientation.** `decodePhoto` =
  `instantiateImageCodec` → `toByteData(rawRgba)` → RGBA→BGRA swizzle; no `image` package.
  D0.5 is proven by a fixture test: a 4×2 JPEG stored sideways with EXIF orientation 6 decodes
  to 2×4 with the right half on the bottom. Fixtures (`test/data/services/photo/fixtures/`)
  were generated with PIL (`~/Documents/marv/mokuro/.venv`): `rgbw_2x2.png` (red, green,
  blue, white) and `exif6_4x2.jpg` (left half black, right half white, `Exif[0x0112] = 6`,
  quality 100, no subsampling).
- **D4.6 (reversed by review, same day) `PhotoPicker` is a domain port.** The first version
  kept the interface under `lib/data/services/photo/` to leave the shared ports directory
  untouched; the review called it a port in all but location (the view model depended on it,
  a fake implemented it). It now lives in `lib/domain/ports/photo_picker.dart` with its row in
  `lib/domain/README.md`; `ImagePickerPhotoPicker` under `lib/data/services/photo/` implements
  it. No UI→data import remains.
- **D4.7 UI patterns.** One `ChangeNotifier` view model, injected by constructor, owned by
  `YomitanukiApp`'s state; no `provider`/`get_it` for one object. One `ListenableBuilder` over
  the body. The OCR panel is an in-tree widget at the bottom of the `Stack`, a function of
  `ocrState`, not `showModalBottomSheet`: testable without the navigator, closable from either
  side, and it cannot outlive the state that opened it. Every UTF-16 unit of the OCR line is
  its own `InkWell` (C15: lookups start at the tapped character; manga-ocr's vocabulary is
  BMP-only, so unit = character). Errors: detector/picker failures are a non-blocking banner
  over the preview (the camera keeps running), camera failures a centred card with a retry,
  OCR/lookup failures inline in the sheet; Anki outcomes are one-shot messages the view shows
  as a snackbar and consumes. `describeReaderError` is the single error→sentence mapping.
  Material 3, seed colour brown, dark theme from the same seed, `ThemeMode.system`; Japanese
  runs get `fontFamilyFallback` (Hiragino on iOS, Noto for a later Android build).
- **D4.8 The AnkiMobile round trip (C14) is the adapter's job.** `CameraFrameSource` registers
  itself as a `WidgetsBindingObserver` in `start()` and removes itself in `stop()`; `paused`
  closes the session (`stopImageStream` + `dispose`), `resumed` reopens it if still wanted.
  `inactive` and `hidden` are ignored: they also fire for the permission prompt and Control
  Centre, and closing there would tear down a session that is wanted a moment later. A reopen
  has no caller to throw to, so its failure goes down the frame stream as a typed error and
  the view model turns it into `CameraFailed` with a retry. The view model's `start`/`stop`
  are screen-level (`ReaderView` init/dispose, photo mode); they do not know about lifecycle.
- **D4.9 `HomeView` is gone; `ReaderView` is the home.** PLAN's placeholder had nothing the
  reader keeps. Routes: `about` (`AboutView`, attribution placeholders for EDRDG, manga-ocr,
  comic-text-detector, Yomitan rules) and, since the WP5 merge, `settings` (WP5's
  `SettingsView` over a fresh `SettingsViewModel` per visit); `YomitanukiApp.routes` takes any
  later ones, and `onUnknownRoute` renders `MissingRouteView` (`lib/ui/core/view/`) instead of
  the framework assertion.
- **D4.10 Typed errors live in `lib/domain/errors.dart`.** `NotWiredError` is an `Error` (a
  build that reaches it is mis-wired), thrown by the `Unavailable…` stand-ins in
  `lib/data/services/unavailable/`; `CameraPermissionDeniedError` and
  `CameraUnavailableError` are `Exception`s mapped from the plugin's `CameraException` codes
  (`CameraAccessDenied`, `…WithoutPrompt`, `CameraAccessRestricted` → permission; anything
  else → unavailable). The test fakes rethrow whatever a test hands them via
  `Error.throwWithStackTrace`, so `only_throw_errors` stays satisfied.
- **D4.11 Camera session seam.** `CameraFrameSource` drives a `CameraSession` interface
  (`initialize`, `startImageStream`, `stopImageStream`, `dispose`, `controller`) through an
  injected `openSession` factory, so permission mapping, pause/resume, throttling and
  rotation are unit-tested against a fake. `PluginCameraSession` is the plugin-backed
  implementation: back camera, `ResolutionPreset.veryHigh` (= `AVCaptureSessionPreset1920x1080`
  in `FLTCam.m`, D0.12), `ImageFormatGroup.bgra8888`, no audio, autofocus and auto-exposure. It
  is four forwarding calls plus the `CameraImage` → `BgraImage` mapping (plane 0, its
  `bytesPerRow`) and is exercised on a device only.
- **D4.12 `make gate-integration` exists and is NOT in `make gate`.** It runs
  `app/integration_test/reader_flow_test.dart` on a booted iOS Simulator (`INTEGRATION_DEVICE`,
  default `iPhone 16`). Kept out of the gate because it needs Xcode, a booted simulator and a
  full iOS build (~1 min warm, minutes cold, plus pod/SwiftPM resolution), none of which the
  gate's `macos-15` job sets up, and a simulator-only failure would block merges that
  `flutter test` already covers. `flutter analyze --fatal-infos` in the gate compiles the
  integration test, so it cannot rot silently. Promote it with the first `flutter build ios`
  step (WP1 notes). It was run once on this Mac: Xcode build 51.6 s, `+1: All tests passed!`.
- **D4.13 What the Simulator can and cannot verify.** Can: layout, fonts (Hiragino renders
  the kanji), the overlay geometry and hit-testing on a real engine, the sheet, the photo
  picker (the simulator has a photo library), theme switching. Cannot: the camera. The
  simulator has no capture device, so `availableCameras()` is empty, `openBackCamera` throws
  `CameraNotFound` and the reader shows the `CameraUnavailableError` card with "Try again";
  that is the expected state, not a bug. Also not verifiable there: the rotation direction
  (D4.3), the permission prompt and its `inactive` transition, 1080p stream throughput and the
  per-frame UI-isolate cost (C12), the AnkiMobile foreground/background round trip. The
  integration test therefore fakes `FrameSource` and proves the UI flow, not the plugin.

- **D4.14 Photo zoom is delivered with the overlay inside the transform.** PLAN §3 WP4 asks for
  a "page view with zoom" on the fallback path. In photo mode the surface and the overlay are
  the child of one `InteractiveViewer` (1×–6×), so `FrameMapping` and the hit-testing are
  untouched: a tap reaches the overlay's `GestureDetector` in the child's own coordinates, and
  the boxes scale with the page. The zoom resets when the source changes. Widget-tested at 2×.
- **D4.15 "Boxes tracked between frames" (PLAN §3 WP4) is moot under D0.13.** Tracking exists
  to carry boxes across the frames between two detections; at ~1 Hz with OCR on tap there is
  nothing to carry: the boxes are redrawn per sample and a tap crops from that sample's frame.
  PLAN §3 WP4 is amended accordingly. If a faster cadence ever returns, tracking returns with
  it.
- **D4.16 A result lands only in the state that asked for it.** Every async operation in the
  reader commits its result conditionally: a detection carries the `_generation` it started in
  and is dropped when `pickPhoto`, `backToCamera` or `stop` bumped it (`dismissOcr` stopped bumping it in
  WP6a, D6a.1); an OCR or
  lookup result is dropped unless its `OcrRunning`/`LookupLoading` object is still the current
  state (`identical`). In the camera adapter a close bumps `_closes`; an open that completes in
  a later generation (stop/paused ran meanwhile) shuts its own session down, and a resume awaits
  a close still in progress before opening. Each case has a Prove-It test that fails without
  the check (review findings 1 and 2).
- **D4.17 Photos are downscaled inside the codec.** `decodePhoto` reads the dimensions with
  `ImageDescriptor.encoded` and instantiates the codec with `targetWidth`/`targetHeight` so the
  long side is ≤ 3000 px (WP0 C7: 3024 px kept 92 % agreement). A 12 MP photo therefore never
  exists as a 48 MB RGBA buffer plus its BGRA copy. EXIF orientation is still applied; the
  4000-px EXIF-6 fixture proves both at once.
- **D4.18 Error text policy.** The screen only ever sees sentences from `describeReaderError`
  (or `AnkiSettings.problems`, which are already sentences); the raw exception goes to the log
  via `_log`. `CameraUnavailableError.reason` is a fixed sentence; the plugin's `code:
  description` is logged once, in the adapter, and nowhere else.

## Red-first evidence

- `test/ui/reader/view_model/reader_view_model_test.dart` and `frame_mapping_test.dart`: run
  before any implementation existed → `Undefined name 'FrameMapping'`, "Some tests failed"
  (compile red); 32 green after `reader_view_model.dart`/`frame_mapping.dart` landed.
- `test/data/services/camera/*`, `test/data/services/photo/*`: run before the adapter files
  existed → `Method not found: 'rotateCw90'`, `'decodePhoto'`, `Type 'CameraSession' not
  found`; then two genuine reds after implementation (the stream tests read synchronously
  from an async broadcast stream) fixed by pumping the event queue in the tests.
- `test/ui/reader/view/reader_view_test.dart`, `test/main_test.dart`: compile red
  (`lib/ui/reader/view/reader_view.dart: No such file`), then five genuine reds: the character
  cells used `Container(alignment: …)`, which expands to the row width, pushing the lazily
  built result cards out of the `ListView` viewport. Fixed in `ocr_sheet.dart`.
- The dismiss-reset test (D4.1) advances only half an interval after `dismissOcr()`; it fails
  without `_lastSampleAt = null`.

## UX self-assessment: holding a book in one hand, the phone in the other

Walked the flow as a reader. Fixed items are marked; the rest are recorded for WP6.

1. **Boxes lag the hand by up to a second** (1 Hz sampling, D0.13). When the phone drifts,
   the boxes drift with the old frame. Tapping crops from that old frame, so the OCR matches
   the box the reader saw, not the live view; correct, occasionally surprising. By design.
2. **Stale boxes after the sheet closes.** Fixed: the first frame after dismiss is detected
   immediately (D4.1; the test now proves it inside the interval, review finding 3b).
3. **The sheet hides the bubble it is about.** The sheet takes 60 % of the screen; the reader
   cannot compare the OCR line with the bubble to judge a misread. Not fixed (WP6); showing
   the crop thumbnail at the top of the sheet (a `BgraImageView` of the crop) is the cheap fix.
3a. **Nothing boxed is a dead end.** Fixed: after three consecutive empty detections a quiet
   hint says "No bubbles found. Move closer or hold steady." and clears on the next hit.
4. **Everything actionable is at the top** (app bar actions, the sheet's close button) and the
   phone is held one-handed. Not fixed; a bottom action row (photo, settings, close) or
   swipe-down-to-close on the sheet would help.
5. **Sampling pauses while the sheet is open.** Intentional: nothing to tap under the sheet,
   and detection would compete with OCR for the device. Side effect of 1 and 2 only.
6. **Scanning feedback is a 2 px progress line** under the app bar. Subtle on purpose; may be
   too subtle in sunlight. Not fixed.
7. **Vertical bubble text is shown horizontally**, wrapping at the sheet width. Readable, but
   the eye has to re-order; furigana is WP6.
8. **Character tap targets are 32×44 px, adjacent.** Fine for a thumb at arm's length;
   dakuten-sized glyphs (っ, ゃ) get the same target. OK.
9. **The lookup highlight follows the longest match**, which is what the reader usually
   wants (食べられなかった, not 食). The other matches are below it, each with its own
   Add-to-Anki. OK.
10. **After Add to Anki, AnkiMobile takes over the screen.** On return the camera restarts
    (D4.8) and the sheet is still open with the entry, so a second word from the same bubble
    is one tap away. The snackbar appears on return. Nothing to fix; note that `dupes` and
    `LSApplicationQueriesSchemes` are WP5's (C14).
11. **Camera permission denied** shows the card with the Settings hint and a retry; it does
    not deep-link to Settings (no extra dependency for one button). Not fixed.
12. **No zoom in the photo view.** Fixed after review (D4.14): pinch to zoom up to 6×, the
    boxes zoom with the page and stay tappable.
13. **The app bar eats preview height.** A transparent app bar over the preview would give
    the page ~56 px more. Not fixed; cosmetic.
14. **Low light / motion blur has no guidance.** OCR on a blurred crop will just read badly.
    Not fixed; needs a device to tune anything.

## Left for WP6 (polish), on purpose

- The sheet hides the bubble it is about (crop thumbnail at the top of the sheet).
- Character cell size (32×44) is one size for all glyphs; small kana get the same target.
- No inline retry on `OcrFailed` / `LookupFailed`; the reader closes the sheet and taps again.
- Vertical bubble text is laid out horizontally; furigana.
- Bottom-reachable actions for one-handed use; transparent app bar over the preview.
- Deep link to the iOS Settings app from the permission card.

## What will bite the integration

- **The integration test is promoted to real ports at the WP2b/WP3 merge.**
  `integration_test/reader_flow_test.dart` fakes every port today, which is why it proves the
  UI flow and not the models. When the ONNX detector/OCR (WP2b) and the SQLite dictionary (WP3)
  land, the same test should boot `AppDependencies.production()` with a synthetic page (P4)
  and keep only `FrameSource`/`AnkiExporter` faked; `make gate-integration` then becomes an
  on-device accuracy smoke test and belongs next to `flutter build ios` in the gate.

- **WP2b (detector, OCR):** replace `UnavailableTextDetector`/`UnavailableOcrEngine` in
  `AppDependencies.production()` (`app/lib/main.dart`) and nowhere else. The detector receives
  the full portrait frame (1080×1920 at the stream preset) and **must honour `bytesPerRow`**:
  an un-rotated iOS BGRA buffer often has row padding, and `orientForPortrait` passes it
  through without repacking (D4.3). Blocks come back in that frame's pixel coordinates.
  Crops handed to the OCR engine are packed (`bytesPerRow == width * 4`), include the 8 %
  margin (D0.6) and are clamped to the frame. Both ports must run off the UI isolate; the
  view model awaits them and nothing else.
- **WP3 (dictionary):** `lookupAt(text, index)` gets the OCR text and a UTF-16 index; results
  are shown longest-first as returned, `start`/`length` drive the highlight. `kanji(literal)` is
  called once per distinct kanji across all matched surfaces (sequentially; batch it in the
  adapter if that is slow).
- **WP5 (Anki, settings) is merged and wired** (`main` merged into this branch after review):
  `UrlLauncherAnkiExporter` and `SharedPreferencesSettingsRepository` are in
  `AppDependencies.production()`, the `settings` route renders WP5's `SettingsView`, and the
  reader loads `AnkiSettings` through the `SettingsRepository` port for every note and builds
  it with `AnkiNoteBuilder` (settings the builder refuses become a message pointing at
  Settings). `AnkiSettings` is WP5's value object; the WP4 stub is gone.
- **Fakes are shared:** `app/test/fakes/` is imported by the integration test via
  `../test/fakes/…`; moving or renaming a fake breaks `integration_test/`. Other branches that
  write their own fakes for the same ports should replace these rather than add a second set.
- **`app/ios`:** `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` are in
  `Info.plist`; iPhone and iPad orientation lists are portrait-only; WP5's `CFBundleURLTypes`
  and `LSApplicationQueriesSchemes` sit next to them. The first simulator build on
  this Mac resolved the plugins without producing a `Podfile` (Flutter 3.47 / Xcode 26 use
  Swift Package Manager), so there is no `Podfile.lock` to commit.
- **Exact names and signatures the other branches plug into:**
  - `AppDependencies({required FrameSource frameSource, required WidgetBuilder cameraPreview,
    required PhotoPicker photoPicker, required TextDetector detector, required OcrEngine ocr,
    required Dictionary dictionary, required AnkiExporter anki, required SettingsRepository
    settingsRepository})`, `AppDependencies.production()` in `app/lib/main.dart`.
  - `YomitanukiApp({required AppDependencies dependencies, Map<String, WidgetBuilder> routes})`.
  - `ReaderViewModel({required FrameSource frameSource, required PhotoPicker photoPicker,
    required TextDetector detector, required OcrEngine ocr, required Dictionary dictionary,
    required AnkiExporter anki, required SettingsRepository settings,
    Duration detectionInterval, double cropMargin, DateTime Function() clock})`.
  - `CameraFrameSource({Future<CameraSession> Function() openSession, Duration emitInterval,
    DateTime Function() clock, WidgetsBinding? binding})`, `CameraPreviewView({required
    CameraFrameSource source})`.
  - `ImagePickerPhotoPicker({Future<Uint8List?> Function()? pickBytes})`,
    `Future<BgraImage> decodePhoto(List<int> encoded)`.
  - `AnkiSettings.defaults` (WP5, `app/lib/domain/models/anki_settings.dart`) and
    `PhotoPicker` (`app/lib/domain/ports/photo_picker.dart`, `Future<BgraImage?> pickPhoto()`).
  - `NotWiredError(String port)`, `CameraPermissionDeniedError()`,
    `CameraUnavailableError(String reason)`, `PhotoDecodeException(String reason)` in
    `app/lib/domain/errors.dart`.
