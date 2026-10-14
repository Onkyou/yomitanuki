# WP6a — live boxes behind the sheet, crop thumbnail, OCR capture log: decision log

Spec: `.claude/wp6a/SPEC.md`. Origin: the first iPhone run, `.claude/wp2/NOTES.md` D2.26.

## Decisions

- **D6a.1 Detection keeps running while the OCR sheet is open (reverses that clause of D4.1).**
  Marv, 2026-10-14, on the device: frozen boxes behind the sheet read as a glitch. The sheet
  is self-contained from tap time on: the crop is a packed copy (D4.2) and now lives in the
  `OcrState`, so a newer `frame` cannot change what the sheet shows or what Anki gets. The
  dismiss-time clock reset and generation bump of D4.1/D4.16 go away with the pause; a
  detection in flight at dismiss now lands. D4.2's budget holds: still one retained frame plus
  one in flight, plus the crop the sheet owns.
- **D6a.2 The selected highlight follows the bubble by IoU, else none.** With live boxes the
  tapped `Rect` stops matching any current box within a second. The overlay highlights the
  current box with IoU ≥ 0.5 against the tapped one; below that nothing is highlighted and the
  thumbnail is the reader's anchor. No tracking is introduced (D4.15 stands).
- **D6a.3 The sheet shows the crop it read.** WP4 UX item 3. `BgraImageView` in a 96 px box.
- **D6a.4 Capture log is a domain port with a file adapter, gated by a persisted switch.**
  `testability-seams`: the file system and the clock are injected. Writes go to the app's
  Documents folder, exposed to Finder/Files via `UIFileSharingEnabled`, because that is the
  only no-server, no-cable-tool way to get crops off the phone. Default off. The switch text says the app sends nothing anywhere and that the folder is
  part of the device backup: Documents is included in iCloud/Finder backups unless excluded,
  and excluding it (`NSURLIsExcludedFromBackupKey`) needs a platform channel, not done
  (review finding). A write failure is logged and swallowed. Pulled captures
  live under `wp0/fixtures/private/` on the Mac (P4).
- **D6a.5 What a capture records, and why.** PNG of the crop plus crop size, frame size, OCR
  time and text. Crop width is the variable the accuracy question hinges on (C7: accuracy fell
  five points between 1920 px and 960 px pages); OCR time is D2.23 item 4, never measured on
  the phone. Scoring is by hand (`truth` column) with `tool/captures/score.py`.

## Red-first evidence

Compile-red means the test file did not compile because the API it names did not exist yet;
assertion-red means a stub with the new shape was in place and the named assertion failed.

T1 (`reader_view_model_test.dart`, `rect_iou_test.dart`, `reader_view_test.dart`)
- 'sampling continues while the OCR sheet is open; the sheet keeps its text and crop when the
  frame changes': compile-red (`OcrText.crop`), then assertion-red `Expected: an object with
  length of <2> / Actual: [Instance of 'BgraImage'] / which: has length of <1>` (detector calls)
  with the sheet still gating `_onFrame`.
- 'selectedBox follows the bubble by IoU and disappears when it moves away' and 'selectedBox is
  null while the sheet is closed': assertion-red `Expected: Rect.fromLTRB(10.0, 10.0, 30.0,
  30.0) / Actual: <null>` against a `selectedBox => null` stub.
- 'dismissOcr does not drop a detection in flight': assertion-red `expect(h.viewModel.scanning,
  isTrue)` (`Expected: true / Actual: false`), because the open sheet still blocked the second
  detection; with detection continuing the remaining assertions pin that dismiss does not drop it.
- `rect_iou_test.dart` (identical, half overlap 1/3, contained 1/4): compile-red, then
  assertion-red `Expected: <1> / Actual: <0.0>` and the 1/3 and 1/4 variants against a
  `rectIou => 0` stub. Disjoint/touching/empty cases pass against the stub by design.
- Existing 'goes running then shows the text' and 'an OCR error is shown in the sheet' gained
  `crop` assertions: compile-red (no `crop` on the states).
- 'the highlighted box follows the tapped bubble as the live boxes move, and goes when it is
  gone' (`reader_view_test.dart`): written after the `ReaderView` change, so not observed red;
  before it the overlay was handed the tapped block's own box, which the shifted-box assertion
  would reject.

T2 (`ocr_sheet_test.dart`)
- 'shows the crop in a 96 px box while reading', 'keeps showing the crop with the text', 'keeps
  showing the crop with the failure': assertion-red `Expected: exactly one matching candidate /
  Actual: Found 0 widgets with key ['ocr.crop']`. 'no crop when idle' passes before and after
  by design. Two existing Anki tests needed `ensureVisible`: the thumbnail pushes the button
  below the sheet's 60 % cap.

T3
- `file_ocr_capture_log_test.dart` (all six): compile-red, `lib/data/services/capture/
  file_ocr_capture_log.dart` did not exist; green on first run of the adapter.
- 'records the crop, text, sizes and timing when the switch is on' and 'an OCR failure records
  empty text and zero time' (`reader_view_model_test.dart`): assertion-red `Bad state: No
  element` from `records.single` with the capture log wired in but nothing recording. 'records
  nothing when off', 'a dismissed read is not recorded' and 'a failing settings load does not
  break reading' pass against the stub by design and guard the implementation.
- 'saving crops is off by default and the flag round-trips' and 'switching crops off removes the
  key' (`shared_preferences_settings_repository_test.dart`): written first, but the repository
  was implemented before the file was run, so no red was observed (compile-red by construction:
  `loadSaveCrops` did not exist).

T4
- `settings_view_model_test.dart` 'save crops (D6a.4)' group (4 tests): compile-red
  (`saveCrops`, `setSaveCrops` undefined).
- `settings_view_test.dart` 'the Diagnostics switch ...' (2 tests): written together with the
  implementation, not observed red separately (the view model tests above were red first).

T5
- `tool/captures/test_score.py` (7 tests): red as `FileNotFoundError: .../score.py`, then one
  assertion failure caused by a wrong expectation in the test (4/11 instead of 4/10), fixed in
  the test, not in the code.

## Reviews (two parallel, 2026-10-14) and what changed

Correctness/readability/security/performance review and architecture-conformance review,
both on the uncommitted diff. No critical finding. Fixed before commit:

- `SettingsViewModel.load` read the Anki settings and the crops flag in one `try`, so a
  failing flag read replaced loaded Anki settings with the defaults. Now two `try`s; test
  'a failing crops load keeps the Anki settings that did load'.
- `setSaveCrops` never cleared a stale error banner on success (D5.7). Fixed; test
  'a successful crops save clears a stale error'.
- "Nothing leaves the phone" was wrong: Documents is in the device backup. Reworded (D6a.4).
- The PNG was named from a second clock at write time; a frozen test clock wrote three PNGs
  to one name unnoticed. Now named from `OcrCapture.at` with a `-n` suffix on collision;
  the adapter takes only the directory. The header test asserts three distinct files.
- `record()` is wrapped in `catchError` in the view model so a future adapter that throws
  cannot become an unhandled async error.
- The TSV sanitiser covers every character Python's `splitlines` breaks on; `score.py`
  splits on LF only and tolerates `150.0` in `crop_w`.
- D4.1 and D4.16 in the WP4 notes carry a pointer to D6a.1.

Mutation checks for the three tests not observed red by the builder, each run against a
deliberate break and restored: 'the highlighted box follows the tapped bubble' (overlay fed
the tapped box again) fails; 'the Diagnostics switch is off by default and saves' (`onChanged`
a no-op) fails; 'clears a stale error' (guard disabled) fails.

Accepted as is: `Future<Directory> Function()` for the directory seam (the spec's sync type
was wrong, `getApplicationDocumentsDirectory` is async); the extra `pump(1 ms)` in widget
tests (the settings fake answers on a timer); `ensureVisible` on the Anki button tests (the
thumbnail pushes it below the 60 % cap on a 600 px test surface, worth a glance on the phone);
a prefs read per OCR completion (cache the flag if WP6b makes it hot).

## Left open

- Which lever to pull on accuracy (D0.12 stream preset or still capture, sharpest-frame
  selection, fp32 OCR) waits for the scored captures.
