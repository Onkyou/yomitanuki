# Handoff, session of 2026-10-14 (first iPhone run, WP6a, WP6b)

**Where the code is:** `~/Documents/marv/manga_ocr`, branch `main`, gate green (`make gate`:
format, analyze `--fatal-infos`, 479 app tests + 33 binding tests, mutation proof, simulator
debug build and unsigned release device build with the ORT symbol verified). Previous handoff
(WP0–WP5, architecture, what will bite) is in git history at `4845dbc`; this one covers only
what changed today.

## The first iPhone run (D2.26 in `.claude/wp2/NOTES.md`)

iPhone 14, iOS 26.6, `flutter run --release`. Signing needed an Apple ID added in Xcode
(Settings › Accounts) before automatic signing could mint a profile; after that the build took
37 s and the install 7 s. Marv's checklist: camera permission flow fine, ORT loads in the release
build, boxes sit on the bubbles (D4.3 holds), AnkiMobile round trip works, lens covered is quiet,
second launch skips the asset copy. The first-launch copy felt slow and was not timed.
Not measured yet: per-stage timings, CoreML partitions, memory (nothing logs them in release).

Two findings drove the rest of the session: boxes froze while the OCR sheet was open, and the
OCR misreads some kanji and struggles with katakana on real pages, with no way to score it.
Three requests followed: readings and a quick-reminder gloss in the sheet, the whole sentence
to Anki, and a visible hint of what is tappable.

## WP6a — live boxes, crop thumbnail, OCR capture log (merged, `.claude/wp6a/`)

- Detection keeps running behind the sheet (D6a.1, reverses that clause of D4.1); the overlay
  highlight follows the bubble by IoU ≥ 0.5 (D6a.2); the sheet shows the crop it read (D6a.3).
- Settings › Diagnostics › **Save OCR crops**: every tapped bubble is written as PNG plus a row in
  `captures.tsv` (timestamp, png, crop and frame size, OCR ms, text) under
  Documents/ocr-captures, visible in Finder › iPhone › Files › Yomitanuki and the Files app
  (D6a.4, D6a.5). Default off. The folder is part of the device backup; the switch says so.
- `tool/captures/score.py captures.tsv`: add a `truth` column by hand, get exact rate and CER
  overall and by crop width (<150, 150–299, ≥300 px), plus the mismatches. Pull the folder to
  `wp0/fixtures/private/` (gitignored, P4).
- Two reviews, fixes folded in (see "Reviews" in the WP6a notes): partial settings load, stale
  error banner, PNG naming, backup wording, TSV sanitiser.

## WP6b — the sentence layer (merged, `.claude/wp6b/`)

Marv's decisions D6b.1–D6b.5: no translation on the device; readings as per-word furigana;
"Add sentence" as a button visible before any word is tapped; underlines for what is tappable.

- `LineGlosser` (domain use case) walks the OCR line with `Dictionary.lookupAt`, left to right,
  taking the first result at each offset (D3.5 already ranks longest-then-best first). Breaks and
  unmatched text are plain spans. Taps still look up at the tapped character (C15); a wrong cut
  costs only a misplaced underline.
- `furigana(surface, form, reading)` (pure) recovers which part of the reading belongs to each
  kanji run by matching the form against the reading as a pattern; inflected surfaces keep the
  shared prefix's ruby and leave the inflection bare; 来る gets く/き/こ by what follows.
- The sheet draws one column per span: ruby over kanji runs, the tappable character cells,
  a 2 px underline in two alternating colours for recognised words, the first gloss under it.
  "Add sentence" (top row, next to close) is enabled once a gloss with at least one recognised
  word is there; the note is Word = the line, Reading = the readings as written, Meaning = one
  `word: gloss` line per word, Example = the line, Note = `sentence`, same deck and note type
  as word notes (D6b.3).
- **Dictionary schema 2**: `forms.reading` is the reading of the matched form, so ビール reads
  ビール instead of 麦酒's ばくしゅ, in the card and in word notes (Word becomes the matched
  form when its reading differs from the headword's). The asset was rebuilt (`make dict`, 68 MB,
  new stamp, recopied on the phone at first launch). `toHiragana` moved to `lib/domain/text/`.
- Two reviews; fixes folded in (see "Review round" in the WP6b notes). Known imperfections are
  listed there: irregular stem changes other than 来る, column width follows the gloss, a very
  long word is scaled down. UX polish (centring, width cap, scale floor) waits for Marv's look.

## How to test the prototype (phone plugged in, unlocked)

```bash
cd ~/Documents/marv/manga_ocr/app && flutter run --release -d 00008110-001C6CD411EA201E
```

1. Open a page; the boxes should keep moving while a sheet is open, and the highlighted box
   should follow its bubble.
2. Tap a bubble: the crop appears at the top of the sheet; the text paints first, then a
   moment later readings over the kanji, underlines in two colours and glosses under the
   recognised words. Check that the Anki button on a word card is still reachable below the
   thumbnail (the sheet caps at 60 % of the screen; scroll inside it if not).
3. Tap "Add sentence": AnkiMobile should open with Word = the line, Reading = kana, Meaning =
   one `word: gloss` per line. Then tap a word and add it the old way; a katakana word such as
   ビール should file as ビール, not 麦酒.
4. Tap a word inside an underlined span and one outside: both must still open the card.
5. Settings › Diagnostics › Save OCR crops on. Tap through two or three pages of Frieren.
6. On the Mac: Finder › iPhone › Files › Yomitanuki › ocr-captures → drag to
   `wp0/fixtures/private/captures-<date>/`. Open `captures.tsv` in Numbers, add a `truth` column
   with the right reading for each row, export as TSV, then:

```bash
python3 -I tool/captures/score.py wp0/fixtures/private/captures-<date>/captures.tsv
```

The by-width buckets answer the accuracy question before anyone touches D0.12 (crop
resolution), sharpest-frame selection, crop margin or fp32 OCR.

## What will bite

- Everything in the previous handoff's list still applies (CI never run, the `camera` stream
  orientation note is now verified on device, memory on 4 GB phones).
- `flutter run --release` does not show `developer.log` output; use `--profile` to see the
  `reader`/`capture` logs.
- The Documents folder is exposed to Finder (`UIFileSharingEnabled`); only `ocr-captures/`
  lives there (models and the dictionary are in Application Support).
