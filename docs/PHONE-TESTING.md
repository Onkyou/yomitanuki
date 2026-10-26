# Testing on a phone

What has and has not run on real hardware, and the checklist for the next phone session.
Decisions and measurements per work package are in `.claude/wpN/NOTES.md`.

## What has run on a phone

The reader, live detection, OCR, dictionary lookup, the sentence layer (WP6b) and the Anki
round trip have run on an iPhone 14 (iOS 26.6) via `flutter run --release` (D2.26 in
`.claude/wp2/NOTES.md`). Signing needed an Apple ID added in Xcode (Settings › Accounts)
before automatic signing could mint a profile. Verified there: the camera permission flow,
ONNX Runtime loading in a release build, boxes sitting on the bubbles (D4.3), the AnkiMobile
round trip, a covered lens staying quiet, the second launch skipping the asset copy.

**WP6c and WP6e have been seen on the phone** (2026-10-20, the README screenshots): the sheet
renders a tapped bubble as a ruby sentence and Apple's Translation framework returns an English
line on the device, so the plugin's first real session, the English-variant resolution and
`translate(batch:)` work. Not yet checked there: the WP6d card shapes inside AnkiMobile (step 5
below), translation quality across more bubbles (step 3), and the capture scoring (steps 7–8).

Not measured yet: per-stage timings, CoreML partitions, memory (nothing logs them in a
release build; the first-launch asset copy felt slow and was not timed).

## Checklist (phone plugged in, unlocked)

```bash
cd app && flutter run --release -d <phone-udid>
```

1. **Language packs first**: Settings › Apps › Translate › Downloaded Languages must have
   Japanese and English (UK or US). The app cannot trigger the download. Then in Yomitanuki,
   Settings › Reading should say "Japanese → English is installed for offline use."
2. Open a page; the boxes should keep moving while a sheet is open, and the highlighted box
   should follow its bubble.
3. Tap a bubble. Expect, top to bottom: the crop (left gutter for a tall bubble, tap it to
   zoom), the line as one ruby sentence with underlines, a grey bar that becomes the English
   translation within about a second, then one row per recognised word. The first bubble shows
   "Tap a character to look it up." once. Note the translation quality on three or four real
   bubbles: this is the first time Apple's model sees manga speech.
4. Swipe the handle down to close; tap another bubble; tap a character: the card opens below the
   word rows with at most three senses and "Add <word>" appears bottom right. Tap a word row too.
5. "Add sentence" and "Add <word>": AnkiMobile should open with the WP6d shapes (sentence: plain
   line, ruby Reading, translation plus a "Words" crib; word: Word = the spelling you saw,
   bold target and ruby in Example, translation in Example (English), tag `yomitanuki`). **Look
   at one of each card in AnkiMobile**: do `<ruby>`, `<b>` and `<details>` render, or does
   `addnote` strip them? That decides whether WP6d's shapes stay.
6. A katakana word such as ビール should file as ビール, not 麦酒.
7. Settings › Diagnostics › Save OCR crops on. Tap through two or three pages of a real book.
8. Energy (WP6f): the preview now runs at 15 fps; is it acceptable while moving the phone, and
   does it flicker under LED room light? Hold the phone still on a page: the scanning indicator
   should come every ~4 s, not every second; turn the page: the boxes follow within about a
   second. Then 20 minutes on one page, unplugged: note the battery drop and whether the back
   warms. No instrumented number exists yet; this is the baseline.
9. On the Mac: Finder › iPhone › Files › Yomitanuki › ocr-captures → drag to
   `wp0/fixtures/private/captures-<date>/` (gitignored, P4). Open `captures.tsv` in Numbers,
   add a `truth` column with the right reading for each row, export as TSV, then:

```bash
python3 -I tool/captures/score.py wp0/fixtures/private/captures-<date>/captures.tsv
```

The by-width buckets answer the accuracy question before anyone touches D0.12 (crop
resolution), sharpest-frame selection, crop margin or fp32 OCR.

## Screenshots for design work

`app/integration_test/screenshots_test.dart` renders the real pipeline on a synthetic page with
a canned translation and saves `app/build/screenshots/{1-sheet-pending,2-sheet,3-card,4-reader,
5-settings}.png` (gitignored). Run with a booted simulator:

```bash
cd app && flutter drive --driver=test_driver/screenshots.dart --target=integration_test/screenshots_test.dart --dart-define=SCREENSHOTS=true -d <simulator-udid>
```

It is skipped under `make gate-integration` (no driver there).

## What will bite

- **Two `make gate` runs at once make the ORT golden tests flake** (three
  `test/data/services/ort` failures under load, green alone). Run one gate at a time.
- `flutter run --release` hides `developer.log`; `--profile` shows the `reader`, `capture` and
  `settings` logs.
- CI (`.github/workflows/ci.yml`) has run on GitHub since the repository went public
  (2026-10-20) and is green; it pins Flutter from `app/pubspec.yaml` and runs `make` on the
  macOS runner.
- Memory on 4 GB phones is unmeasured.
- The Documents folder is exposed to Finder (`UIFileSharingEnabled`); only `ocr-captures/`
  lives there (models and the dictionary are in Application Support).
