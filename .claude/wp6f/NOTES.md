# WP6f — energy: the camera streams only when asked, detection runs only when the page changed

Marv, 2026-10-26: "what I actually do most of the time is open the app, start reading my manga,
and keep it open the whole time … if we detect no movement, or no changes in the camera image,
we could throttle the processing significantly." After the assessment (below) he chose: "Skip the
measurement. Spec and build the camera-side changes: pin a lower fps, duty-cycle the image stream
around each sample, then the change-gated detection backoff."

## What the assessment found

Detection already runs once a second on CoreML (~30–40 ms per pass, WP2 §measurements) and is
the *small* part of the bill. The part nobody throttled is the plugin: `camera_avfoundation`
0.10.3+1 (`DefaultCamera.swift`, `handleSampleBufferStreaming`) copies **every** sensor frame into
a `Data`, wraps it for the platform channel and dispatches it to the main thread; the Dart side
allocates a fresh ~8 MB `Uint8List` per 1080p frame, at the camera's native rate (30 fps), with
at most four frames in flight. `CameraFrameSource` looked at the clock only *after* all of that,
and used one frame in thirty. The D4.2 note ("the plugin's own channel decode plus one `DateTime`
compare") undersold that cost; it is the likely source of the warm phone on a long read.

The plugin can pin the capture frame rate: `CameraController(fps:)` → `PlatformMediaSettings.
framesPerSecond` → `FormatUtils.findBestFormat` keeps the 1080p format and sets
`activeVideoMinFrameDuration == activeVideoMaxFrameDuration == 1/fps` on the device. Apple names
lowering that duration as the response to rising `systemPressureState`. It is construction-time
only (no runtime setter), so the dynamic part has to live in the stream duty cycle, not the rate.
`startImageStream`/`stopImageStream` on iOS flip a flag checked before the copy; the preview keeps
running with the stream off.

## Decisions

- **D6f.1 The camera streams only while a frame is wanted.** `FrameSource` gains
  `void requestFrame()`: the consumer asks for *the next* frame; the source delivers exactly one
  frame per outstanding request on `frames` (requests before delivery coalesce into one). While no
  request is outstanding the plugin image stream is **off**; the preview is untouched. In
  `CameraFrameSource`: `_frameWanted` (bool) and `_streaming ∈ {off, starting, on, stopping}`;
  `requestFrame()` sets the flag and reconciles (`_syncStream`): start the stream when wanted and
  off, stop it when not wanted and on; a request that lands while *stopping* starts it again once
  the stop has settled; a start or stop that completes after its session was closed (the
  generation guard of D4.16: `identical(session, _session)`) touches nothing further, because
  `dispose()` takes the stream with it. `_onImage` drops a frame when nothing is wanted (the stop
  is in flight), otherwise clears the flag, emits the oriented frame and reconciles (→ stop).
  `_open` no longer starts the stream; it reconciles after assigning `_session`. `_shutDown` calls
  `stopImageStream` only when `_streaming == on` (the plugin throws when it is not streaming) and
  always disposes. **A request outstanding across pause/resume is honoured after the reopen**
  (`_frameWanted` survives `_close`, which is what lets the view model's timer fire while the app
  is backgrounded without anyone retaining a frame); `stop()` clears it. `emitInterval` and the
  adapter's `clock` seam go: one frame per request needs no throttle.
- **D6f.2 Sampling is request-driven, with the timer in the view model (revises D4.1).**
  `ReaderViewModel` takes `sampleInterval` (default 1 s, D0.13; replaces `detectionInterval`) and
  a seam `Timer Function(Duration, void Function()) createTimer = Timer.new`. After
  `_frameSource.start()` succeeds it requests at once (`_awaitingFrame = true;
  _frameSource.requestFrame()`); `_onFrame` drops any frame while `_source != camera`,
  `_inFlight > 0` or `!_awaitingFrame`, else clears the flag, handles the sample (D6f.3), and when
  that has settled schedules the next request `sampleInterval` later. The timer is cancelled and
  `_awaitingFrame` cleared by `stop()`, `dispose()` and a stream error (`CameraFailed`; `start()`
  from the retry button begins a new cycle). A request is only ever issued while
  `_source == camera`, `_cameraState is CameraLive` and not disposed. D4.1's two objections to a
  timer no longer hold: no frame is retained between ticks (the tick asks for a fresh one) and a
  tick while the camera is closed costs one boolean in the adapter. The `_clock` seam stays for the
  capture log timestamps only; `_lastSampleAt` goes.
- **D6f.3 The detector runs when the frame changed, and at least every 4th sample while it did
  not.** Pure function `changedCellFraction(BgraImage before, BgraImage after)` in
  `lib/domain/use_cases/frame_change.dart`: the image is a 24×24 lattice of cells; in each cell the
  pixels at the cell origin and every `stride = 8` px after it in x and y are read (so a 100×100
  test image still yields ≥ 1 sample per cell); per-cell mean luminance `(77·R + 150·G + 29·B) >> 8`
  on the BGRA bytes, honouring `bytesPerRow`; a cell *changed* when the means differ by more than
  10; the result is `changed cells / cells`, and `1.0` when the two images differ in size. Cost at
  1080×1920: ~32 k pixel reads per image, well under a millisecond. The view model compares the
  sample against **the frame its current blocks came from** (`_frame`, already retained, so no new
  buffer; comparing against the last *sample* would let a slow drift never trigger) and skips the
  detector when the fraction is `< changeThreshold = 0.03` **and** fewer than
  `stillRedetectEvery = 4` samples have passed since the last detection; the periodic re-detect
  keeps a bubble the detector missed once from staying missed while the page is still. A skipped
  sample is dropped (not retained); `_frame`, `blocks`, `selectedBox`, `emptyRuns`,
  `noBlocksHint` and `scanning` are untouched by a skip. The function is injected
  (`frameDifference` constructor seam, default `changedCellFraction`): the test images differ by
  one byte per pixel between seeds (R = seed), which the real metric rightly calls "still", so the
  harness defaults to `(_, __) => 1.0` and the gating group alone uses the real function.
  Sampling itself stays at 1 Hz: the camera copy is already down 30× from D6f.1, the diff is
  cheap, and the boxes still follow a page turn within a second (the lag of D4 §"what will bite"
  does not grow). **This refines D0.13**: "detection at ~1 Hz" becomes "sampled at 1 Hz, detected
  on change and at least every 4 s".
- **D6f.4 The camera is pinned to 15 fps.** `openBackCamera` passes `fps: 15`. Sensor, ISP,
  preview compositing and whatever the plugin still does per frame all halve; the preview is a
  little less fluid while the phone moves. Auto-exposure may now use up to 1/15 s, which is more
  motion blur in a dim room and a brighter frame; the OCR crop is taken from a sampled frame, not
  the preview, so the phone-test checklist gets a line for it. Untested off the device, like the
  rest of `openBackCamera`.
- **D6f.5 Not in this package:** thermal/pressure feedback (needs a platform channel; the plugin
  exposes neither `ProcessInfo.thermalState` nor `systemPressureState`), a different sample rate
  per state, and the idle timer (the app does not disable auto-lock, and locking is the biggest
  saving there is). Measured numbers: none yet; Marv skipped the A/B on purpose. If the warm-phone
  symptom survives this package, measure before touching anything else.

## Packages (each lands with `dart format`, `flutter analyze --fatal-infos`, `flutter test` green)

1. **Request-driven sampling in the view model** (D6f.2; port + fake + VM + tests). The adapter
   implements `requestFrame()` as a no-op and keeps streaming, so the app behaves as before.
2. **Duty-cycled adapter and 15 fps** (D6f.1, D6f.4; adapter + its tests).
3. **Change-gated detection** (D6f.3; `frame_change.dart` + tests, VM + tests).

## Phone checklist additions (docs/PHONE-TESTING.md)

- Preview at 15 fps: acceptable while moving the phone? Any flicker under LED room light?
- Phone held still on a page: the scanning indicator should come every ~4 s, not every second;
  turn the page: boxes follow within about a second.
- 20 minutes on one page, phone unplugged: note the battery drop and whether the back warms, for
  comparison with earlier sessions (no instrumented number exists; this is the baseline).
