# Spec: WP6a — live boxes behind the sheet, crop thumbnail, OCR capture log

Branch `wp6a-live-sheet-captures` off `main`. Decisions in `.claude/wp6a/NOTES.md` (D6a.x);
the WP4 decisions they touch are named there. Read before coding: `AGENTS.md`,
`.agents/skills/flutter-apply-architecture-best-practices`, `test-driven-development`,
`testability-seams`, `flutter-add-widget-test`, `error-handling-conventions`.

## Objective

Three findings from the first iPhone run (`.claude/wp2/NOTES.md` D2.26):

1. Boxes freeze while the OCR sheet is open and jump on dismiss. Detection must keep running
   behind the sheet (reverses the sheet condition of D4.1).
2. The sheet covers the bubble it is about. The sheet shows the crop it read at its top.
3. OCR misreads kanji and katakana on real pages and nobody has scored a camera crop. A
   diagnostics switch saves every tapped crop with its reading, size and timing to a folder
   the reader can pull from Finder, so accuracy can be scored by hand and correlated with
   crop size before any inference change is chosen.

Out of scope: any change to detection interval, crop margin (8 %, D0.6), stream preset
(D0.12), models, decoding. No new code generators (D1.x).

## Tech stack and commands

Flutter app in `app/`; `dart format`, `flutter analyze --fatal-infos`, `flutter test` run from
`app/`. Builder runs those three; the orchestrator runs `make gate` (iOS builds) afterwards.
Do not add packages: `path_provider` and `shared_preferences` are already dependencies;
PNG encoding uses `dart:ui` (`decodeImageFromPixels` + `toByteData(png)`), as
`lib/ui/reader/view/bgra_image_view.dart` already decodes.

## Structure (files to touch)

```
app/lib/ui/reader/view_model/reader_view_model.dart   gating, OcrState carries crop, selectedBox, capture call
app/lib/ui/reader/view_model/reader_state.dart        OcrRunning/OcrText/OcrFailed gain `crop`
app/lib/ui/reader/view/ocr_sheet.dart                 thumbnail
app/lib/ui/reader/view/reader_view.dart               `selected:` from vm.selectedBox
app/lib/domain/ports/ocr_capture_log.dart             NEW port
app/lib/domain/models/ocr_capture.dart                NEW value (what one record holds)
app/lib/domain/ports/settings_repository.dart         + saveCrops flag
app/lib/data/repositories/shared_preferences_settings_repository.dart
app/lib/data/services/capture/file_ocr_capture_log.dart   NEW adapter (Documents/ocr-captures)
app/lib/ui/settings/view_model/settings_view_model.dart   + saveCrops
app/lib/ui/settings/view/settings_view.dart               + Diagnostics section
app/lib/main.dart                                        wiring
app/ios/Runner/Info.plist                                UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace
tool/captures/score.py                                   NEW, stdlib only
tests next to each, plus the fake capture log in test/ fakes
```

## Tasks (in order; each lands with its tests red first, then green)

### T1 Detection continues while the sheet is open

- `ReaderViewModel._onFrame` drops the `_ocrState is! OcrIdle` condition. Interval, in-flight
  and source checks stay.
- `dismissOcr` no longer bumps `_generation` and no longer resets `_lastSampleAt`: boxes are
  already live. It only clears `_ocrState`/`_lookupState` and notifies.
- `OcrRunning`, `OcrText`, `OcrFailed` gain `final BgraImage crop` (the packed copy made at
  tap time; constructor order `(block, crop, …)`). Nothing in the sheet depends on `frame` any
  more.
- `ReaderViewModel.selectedBox` (`Rect?`): while `_ocrState` is not `OcrIdle`, the box among
  the current `blocks` with the highest IoU against the tapped `block.box`, if that IoU is
  ≥ 0.5; else `null`. `ReaderView` passes it as `BlockOverlay.selected` instead of the
  tapped block's own box. IoU is a pure function in `reader_view_model.dart` or a small
  `lib/ui/reader/view_model/rect_iou.dart`, unit-tested.
- Tests (`test/ui/reader/view_model/reader_view_model_test.dart`): replace
  'sampling pauses while the OCR sheet is open …' with
  (a) 'sampling continues while the OCR sheet is open; the sheet keeps its text and crop when
  the frame changes' — open the sheet, advance 1 s, emit frame seed 2, expect detector calls 2,
  `ocrState` still the same `OcrText` with `crop.bytes[2] == 1` (from frame 1), `frame` is the
  new frame;
  (b) 'selectedBox follows the bubble by IoU and disappears when it moves away' — detector
  returns the same box shifted by 2 px → selected is the shifted box; returns a box far away
  → `null`;
  (c) 'dismissOcr does not drop a detection in flight' — hold the detector, dismiss, release,
  expect the blocks landed.
  Keep every existing D4.16 test green.

### T2 Crop thumbnail in the sheet

- `OcrSheet` shows `BgraImageView(image: state.crop)` inside `SizedBox(height: 96)` with
  `Key('ocr.crop')` above the OCR line, for `OcrRunning`, `OcrText` and `OcrFailed`.
  `BgraImageView` uses `SizedBox.expand`, which a `ListView` child cannot; the fixed-height
  box gives it bounds. Padding 16 horizontal, 8 below.
- Widget test (`test/ui/reader/view/reader_view_test.dart` or a new `ocr_sheet_test.dart`):
  the key is present for all three states and absent for `OcrIdle`.

### T3 OCR capture log

- Domain value `OcrCapture`: `crop` (`BgraImage`), `frameWidth`, `frameHeight` (ints), `text`
  (`String`, empty on failure), `elapsed` (`Duration`; `Duration.zero` on failure),
  `at` (`DateTime`).
- Port `OcrCaptureLog { Future<void> record(OcrCapture capture); }`.
- Adapter `FileOcrCaptureLog(Directory Function() documentsDirectory, DateTime Function() clock)`
  — directory function injected (default `getApplicationDocumentsDirectory` in `main.dart`,
  a temp dir in tests). Writes to `<documents>/ocr-captures/`:
  `yyyyMMdd-HHmmss-SSS.png` (PNG of the crop via `dart:ui`) and appends one line to
  `captures.tsv`: `timestamp \t png \t crop_w \t crop_h \t frame_w \t frame_h \t elapsed_ms \t text`.
  Tabs and newlines in `text` are replaced by a space. Create the directory and a header line
  on first write. Any failure is logged via `developer.log(name: 'capture')` and swallowed: a
  diagnostics write never breaks reading (`error-handling-conventions`).
- Test: a temp directory, two records (one text, one failure), assert the TSV has header + 2
  lines with the expected columns and both PNGs exist and decode (`dart:ui` decode in a
  `flutter_test` is fine, or check the PNG signature bytes).
- `SettingsRepository` gains `Future<bool> loadSaveCrops()` / `Future<void> saveSaveCrops(bool)`;
  key `debug.saveCrops`, removed when false (same pattern as `_put`). Fake and shared-prefs
  tests updated.
- `ReaderViewModel` takes `required OcrCaptureLog captureLog`. In `onTapBlock`, after the
  result lands (success or failure, and only if still current per D4.16), it does
  `if (await _settings.loadSaveCrops()) unawaited(_captureLog.record(...))` with the frame's
  dimensions. Tests with a fake log: records when the flag is on, with the right text and
  frame size; nothing when off; a failure records empty text.

### T4 Settings: Diagnostics section

- `SettingsViewModel` loads and exposes `saveCrops` (bool) and `setSaveCrops(bool)`.
- `SettingsView` gets `_Section(title: 'Diagnostics')` after 'Field names' with a
  `SwitchListTile` keyed `SettingsView.saveCropsKey`, title 'Save OCR crops', subtitle
  'Saves each tapped bubble and its reading under Files › Yomitanuki › ocr-captures, for
  checking accuracy. Nothing leaves the phone.'
- `ios/Runner/Info.plist`: `UIFileSharingEnabled` true, `LSSupportsOpeningDocumentsInPlace`
  true, with a one-line XML comment naming WP6a, so Finder and the Files app expose Documents.
- Widget test: toggling the switch calls the repository with true.

### T5 Scoring helper

`tool/captures/score.py` (Python 3 stdlib, run with `-I`): reads a `captures.tsv` to which
Marv has added a trailing `truth` column by hand; prints exact-match rate and character error
rate (Levenshtein / len(truth)) overall and bucketed by `crop_w` (< 150, 150–299, ≥ 300),
plus the per-row diff for mismatches. Rows without `truth` are skipped and counted. A 20-line
docstring says how to pull the folder (Finder › iPhone › Files › Yomitanuki) and that it must
land under `wp0/fixtures/private/` (gitignored, P4). A doctest or a tiny `test_score.py`
beside it is enough.

## Boundaries

- Never commit anything from `ocr-captures/`; `.gitignore` already covers `wp0/fixtures/private/`.
- No new dependency, no code generation, no change under `wp0/`.
- `make gate` must stay green: `dart format`, `analyze --fatal-infos`, all tests, mutation proof.

## Success criteria

- All T1–T4 tests red before and green after; full `flutter test` green; analyzer clean.
- On the phone: boxes keep moving behind the sheet; the thumbnail shows the bubble; with the
  switch on, `ocr-captures/` appears in Finder with PNGs and a TSV after a few taps.

## Open questions

None that block. If `BgraImageView` in a 96 px box misbehaves in widget tests (decode is async
and blank in tests), the test asserts the key only.
