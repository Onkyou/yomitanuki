# Handoff, sessions of 2026-10-14/15 (first iPhone run, WP6a–WP6e)

**Where the code is:** `~/Documents/marv/manga_ocr`, branch `main`, gate green (`make gate`:
format, analyze `--fatal-infos`, 577+ app tests + 33 binding + 10 translation-plugin tests, mutation proof, simulator
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

## WP6c — on-device sentence translation (merged, `.claude/wp6c/`)

Marv, after using WP6b: word glosses alone are hard on the UX; a full-sentence translation,
offline, high quality. Decisions D6c.1–D6c.6.

- Apple's Translation framework through a Swift method-channel plugin,
  `app/packages/translation_ios`. On iOS 26 the session is created directly for installed
  languages (`TranslationSession(installedSource:target:)`, verified against Apple's doc data),
  high-fidelity model on 26.4+, English variant resolved GB → US → en (Marv installed UK
  English). Below iOS 26 the feature reports "needs iOS 26"; deployment target stays 15.1,
  `Translation` is weak-linked. **The app cannot trigger the language download**: the packs are
  installed under Settings › Apps › Translate › Downloaded Languages (Japanese + English);
  Settings › Reading shows the status and that path.
- `SentenceTranslator` port + adapter; the view model translates alongside the gloss and lands
  both by crop identity (D6c.3); the sheet shows the line (pending state while it runs);
  both Anki notes carry it as Example (English) (D6c.4); Settings › Reading › "Translate
  sentences", on by default (D6c.5).
- Two reviews; fixes: single-flight translate calls in the plugin (two quick taps would have
  shared one session), a removed pack caches its status instead of showing the pending state on
  every tap, CI moved to `macos-26` (the Swift needs the iOS 26 SDK), the plugin's tests in
  `make gate`/CI, Podfile.lock updated.
- **Not run on a phone yet.** Verified on the simulator with a fake translator only (the
  framework does not run there). Android later: Google ML Kit on-device translation is the
  equivalent adapter behind the same port (notes).

## WP6d — Anki card shape (merged, `.claude/wp6d/`)

From a design review of the cards (findings and before/after tables in the notes), D6d.1–D6d.6:
word notes have Word = the spelling the reader saw deinflected (ちょっと stays ちょっと, ビール
stays ビール; it used to send 一寸 and 麦酒), at most three senses with the matching ones first,
the target in bold and `<ruby>` furigana on the other words in Example; sentence notes are a
JP → EN recognition card: plain line in Word, ruby line in Reading, translation plus a
`<details>` crib of word glosses in Meaning, Example/ExampleEN/Note empty, optional separate
"Sentence note type" in Settings; every note tagged `yomitanuki`, sentence notes also
`sentence`. **Check one real card in AnkiMobile**: whether `addnote` keeps `<ruby>`, `<b>` and
`<details>` (WebKit renders them; the scheme's handling is unverified). Template advice for
Marv is in the WP6d notes (furigana Reading on the back only, glosses in `<details>`).

## WP6e — the sheet as a sentence (merged, `.claude/wp6e/`)

From a UI/UX review over simulator screenshots (findings, decisions D6e.1–D6e.7 and the
parked items in the notes; before/after screenshots were sent to Marv's phone):
the line is one ruby sentence with glyph-wide tap cells and word underlines; Japanese first,
then the translation marked with a translate icon (a skeleton while pending, no layout shift);
then one compact row per recognised word (surface, reading, short gloss, "+N"; particles and
auxiliaries keep their underline but get no row); the crop thumbnail is sized by aspect as a
left gutter or a top banner and zooms full screen; grab handle and swipe-to-close; a sticky
bottom bar with "Add sentence" and "Add <word>"; the card shows at most three senses, matched
first, kanji folded, later results as rows; the tap hint shows once per session; a missing
language pack raises one quiet note pointing at Settings. Two reviews; the real defect found
(the thumbnail gutter pinning the header to 140 pt) was fixed with a red-first test.
Parked: transparent app bar, a pulse instead of the scanning line, collapsing the field-name
inputs, an undo for "Reset to defaults".

## Screenshots for design work

`app/integration_test/screenshots_test.dart` renders the real pipeline on a synthetic page with
a canned translation and saves `app/build/screenshots/{1-sheet-pending,2-sheet,3-card,4-reader,
5-settings}.png` (gitignored). Run with a booted simulator:

```bash
cd ~/Documents/marv/manga_ocr/app && flutter drive --driver=test_driver/screenshots.dart --target=integration_test/screenshots_test.dart --dart-define=SCREENSHOTS=true -d AE19C697-FC9D-43D8-94DB-291349B16DF8
```

It is skipped under `make gate-integration` (no driver there).

## How to test the prototype (phone plugged in, unlocked)

```bash
cd ~/Documents/marv/manga_ocr/app && flutter run --release -d 00008110-001C6CD411EA201E
```

1. **Language packs first**: Settings › Apps › Translate › Downloaded Languages must have
   Japanese and English (UK or US). Then in Yomitanuki, Settings › Reading should say
   "Japanese → English is installed for offline use."
2. Open a page; the boxes should keep moving while a sheet is open, and the highlighted box
   should follow its bubble.
3. Tap a bubble. Expect, top to bottom: the crop (left gutter for a tall bubble, tap it to
   zoom), the line as one ruby sentence with underlines, a grey bar that becomes the English
   translation within about a second, then one row per recognised word. The first bubble shows
   "Tap a character to look it up." once. Note the translation quality on three or four real
   bubbles: this is the first time Apple's model sees manga speech.
4. Swipe the handle down to close; tap another bubble; tap a character: the card opens below the
   word rows with at most three senses and "Add <word>" appears bottom right. Tap a word row too.
5. "Add sentence" and "Add <word>": AnkiMobile should open with the new shapes (sentence: plain
   line, ruby Reading, translation plus a "Words" crib; word: Word = the spelling you saw,
   bold target and ruby in Example, translation in Example (English), tag `yomitanuki`). **Look
   at one of each card in AnkiMobile**: do `<ruby>`, `<b>` and `<details>` render, or does
   `addnote` strip them? That decides whether WP6d's shapes stay.
6. A katakana word such as ビール should file as ビール, not 麦酒.
7. Settings › Diagnostics › Save OCR crops on. Tap through two or three pages of Frieren.
8. On the Mac: Finder › iPhone › Files › Yomitanuki › ocr-captures → drag to
   `wp0/fixtures/private/captures-<date>/`. Open `captures.tsv` in Numbers, add a `truth` column
   with the right reading for each row, export as TSV, then:

```bash
python3 -I tool/captures/score.py wp0/fixtures/private/captures-<date>/captures.tsv
```

The by-width buckets answer the accuracy question before anyone touches D0.12 (crop
resolution), sharpest-frame selection, crop margin or fp32 OCR.

## What will bite

- **Nothing from WP6c–WP6e has run on a phone.** The simulator verified the pipeline with a
  fake translator (Apple's framework does not run there) and the sheet layout; the Swift plugin
  compiled in the gate and was type-checked against the SDK, but its first real session,
  the English-variant resolution and `translate(batch:)` happen on Marv's phone.
- **Two `make gate` runs at once make the ORT golden tests flake** (three `test/data/services/ort`
  failures under load, green alone). Run one gate at a time.
- `flutter run --release` hides `developer.log`; `--profile` shows the `reader`, `capture` and
  `settings` logs.

- Everything in the previous handoff's list still applies (CI never run, the `camera` stream
  orientation note is now verified on device, memory on 4 GB phones).
- `flutter run --release` does not show `developer.log` output; use `--profile` to see the
  `reader`/`capture` logs.
- The Documents folder is exposed to Finder (`UIFileSharingEnabled`); only `ocr-captures/`
  lives there (models and the dictionary are in Application Support).
