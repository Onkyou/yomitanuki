# yomu: plan and locked decisions

Working name (読む, "to read"). Rename freely before WP1.

A personal Flutter app for reading **physical** manga with instant lookups: point the camera at a
page, the app boxes the speech bubbles live, tap one, get the text, tap a word, get the dictionary
entry, one tap adds it to Anki. Everything runs on the phone. (Name: Yomitanuki, D9.)

Written 2026-10-13. This file is the starting point for a fresh Claude Code session.

---

## 0. Locked decisions

| # | Decision | Locked | Why |
|---|---|---|---|
| D1 | Flutter | 2026-10-13 | Android support wanted eventually. iOS is the only v1 target. |
| D2 | Fully on device | 2026-10-13 | No server, no network dependency while reading. |
| D3 | Automatic bubble detection from the start | 2026-10-13 | Tap a bubble instead of dragging a crop box. |
| D4 | iOS only for v1 | 2026-10-13 | Android is a later work package, not a v1 constraint. |
| D5 | wegziel's engineering practices apply | 2026-10-13 | See §4. |
| D6 | Model weights ship **inside the app bundle** (replaces P2) | 2026-10-13 | WP0 cut the weights to 165 MB (detector fp16 + OCR int8); Marv prefers the simpler build over a Files-app import. |
| D7 | Dictionary glosses in English only for v1 | 2026-10-13 | German can be added later from the same JMdict build. |
| D8 | P1, P3, P4 confirmed | 2026-10-13 | P1 by WP0 measurement (`.claude/wp0/NOTES.md`), P3 and P4 accepted without change. |
| D9 | App name **Yomitanuki** (読みたぬき), bundle id `app.mcmaffin.yomitanuki` | 2026-10-13 | Yomitan + tanuki, the Shigaraki statue that holds an account book. (findling uses `com.mcmaffin.findling.app`; Marv asked for the `app.mcmaffin` form here.) |
| D10 | **Live detection is the target UX**: bubbles are boxed on the camera stream, tapping one OCRs it. A still photo is the fallback path, not the design centre. | 2026-10-13 | Marv wants the dynamic case. WP2 gates on an on-device detector frame rate; WP4 is built around the camera image stream. |

### Proposals (resolved 2026-10-13: P1/P3/P4 confirmed, P2 replaced by D6)

| # | Proposal | Reasoning |
|---|---|---|
| P1 | **ONNX Runtime** as the single inference runtime (CoreML execution provider on iOS, NNAPI/XNNPACK on Android later) | D1 + D4: one model format and one Dart code path for both platforms. The earlier idea of converting to CoreML would have to be redone for Android. Native CoreML conversion stays as a fallback only if WP0 shows ORT is too slow. |
| P2 | Models are **not** bundled in the app binary; copied in once (Files app / first-run download from own storage) | ~150-450MB of weights makes every Xcode build and install slow. |
| P3 | Word segmentation by **deinflection rules + longest match against JMdict**, no MeCab | Small, pure Dart, testable. MeCab/Sudachi on mobile means native libs and a 50MB+ dictionary. |
| P4 | Test fixtures for CI are **synthetic** (Japanese text rendered onto images); photos of my own book pages stay local and gitignored | Keeps the repo clean of book content while still giving real-page accuracy checks locally. |

---

## 1. Pipeline

```
camera / photo
   │
   ▼
[1] text detection      comic-text-detector (YOLO-based, the model mokuro uses)
   │                    input 1024x1024 → text blocks + line mask
   ▼
[2] user taps a block
   │
   ▼
[3] OCR                 manga-ocr (kha-white/manga-ocr-base)
   │                    ViT encoder (224x224) + char-level Japanese BERT decoder,
   │                    greedy decode loop in Dart
   ▼
[4] segmentation        deinflect + longest match against JMdict (P3)
   │
   ▼
[5] lookup popup        JMdict (words) + KANJIDIC2 (kanji), SQLite on device
   │
   ▼
[6] add to Anki         AnkiMobile URL scheme  anki://x-callback-url/addnote?...
```

**Anki target** (matches the existing deck so cards merge cleanly):
- deck `Japanese::Frieren Vol. 1` (configurable per book)
- note type `Frieren Vocab (JP→EN)`, fields `Word, Reading, Meaning, Example, ExampleEN, Note`
- `Example` gets the OCR'd bubble line, so every card has its real context sentence.

**Data sources and licences**
- JMdict / KANJIDIC2: EDRDG licence (CC BY-SA 4.0). Use the `jmdict-simplified` JSON builds, converted to SQLite by a build script. Attribution screen required.
- Deinflection rules: Yomitan's are GPL-3.0. Fine for a personal app; if this is ever distributed, write own rules or check licence compatibility first.
- manga-ocr: Apache-2.0. comic-text-detector: GPL-3.0 (same caveat as above).

---

## 2. Existing assets on this Mac

- `~/Documents/marv/mokuro/.venv` already has `manga_ocr`, torch and fugashi installed. WP0 can start from it.
- `~/Documents/marv/wegziel` is the reference for process and gates (§4).
- `~/Documents/marv/learning_tool` is a separate earlier project; not part of this.

---

## 3. Work packages

Each WP names its first tests before its scope. A WP is done when `make gate` is green and both
reviews in §4.3 are clean.

### WP0: feasibility spike (Python, no app code)
The riskiest part is the manga-ocr decoder export, so it is proven before any UI exists.
- Export comic-text-detector to ONNX (or use the published ONNX file) and run it in Python with `onnxruntime`.
- Export manga-ocr with `optimum` (encoder and decoder as separate graphs). Reimplement the greedy decode loop by hand against ORT, outside `transformers`, because that loop is what Dart has to reproduce.
- Quantise (dynamic int8 for the decoder, fp16 for the encoder as a first try).
- Measure on ~30 bubbles from my own photos: **character error rate fp32 vs quantised**, latency, file sizes.
- **Exit:** numbers recorded in `.claude/wp0/NOTES.md`, P1 confirmed or rejected, size budget decided.

### WP1: scaffold and gate
- `flutter create`, iOS only enabled. Strict analysis (flutter_lints plus stricter rules, `--fatal-infos`).
- `Makefile` with `make gate` == `.github/workflows/ci.yml`, line for line (§4.1).
- Layering per `flutter-apply-architecture-best-practices`: `ui/<feature>/{view, view_model}`, `domain/models`, `data/{services, repositories}`.
- First tests: a gate mutation proof (a deliberately unformatted / lint-violating fixture must turn the gate red).

### WP2: inference core behind ports
- **First task, gating (D10): on-device frame rate of the blocks-only detector** (fp16, CoreML EP,
  640 and 1024 input) on the target iPhone. Target ≥ 5 fps for live boxes; below ~2 fps the live path
  is cut and WP4 falls back to still photos with a single detection pass.
- Ports: `TextDetector`, `OcrEngine`. ORT adapters implement them; fakes implement them for every other test.
- Image preprocessing (resize, normalise, crop from detected box) as pure Dart, unit tested.
- Decoder loop in Dart, tested against the token sequences recorded in WP0 (same input → same tokens).
- Inference runs off the UI isolate.
- First tests: preprocessing golden values; decode-loop parity with WP0; synthetic-image OCR returns the rendered string.

### WP3: dictionary
- Build script: jmdict-simplified + KANJIDIC2 → SQLite asset, with an indexed reading/kanji lookup.
- Deinflector + longest-match segmenter.
- First tests: a conjugation table (食べられなかった → 食べる, 行って → 行く, 強そう → 強い, 来るはず → 来る + はず, 知っています → 知る), plus segmentation of whole lines.

### WP4: capture and reader UI
- Live camera stream (D10): detector runs on downscaled frames off the UI isolate, boxes are drawn
  over the preview and tracked between frames; tapping a box OCRs the crop from a full-resolution
  frame. Photo picker and page view with zoom as the fallback path.
- Tap block → OCR text with each word tappable → lookup popup (reading, meanings, kanji breakdown).
- Widget tests with fake ports; one integration test on simulator with a synthetic page.

### WP5: Anki export
- Build the `addnote` URL from a lookup result + context line; deck and note type configurable.
- First tests: URL encoding of Japanese text and field mapping.

### WP6: polish
- Saved-words history, per-book settings, furigana rendering for the OCR line, performance pass.

### WP7: Android bring-up (later)
- ORT NNAPI/XNNPACK provider, AnkiDroid's API instead of the URL scheme, camera permissions.

---

## 4. Practices carried over from wegziel

### 4.1 The gate
- **`make gate` and CI run the same commands** and are meant to be diffed. A gate that exists only in CI is found after a push; one that exists only locally gets skipped.
- **Whole-tree checks from commit one, no baseline.** A violation that reaches main is outside every later diff and becomes unreportable.
- Tool versions pinned in one place and asserted equal in Makefile and CI. Make recipes open with `set -eo pipefail;` (macOS ships GNU Make 3.81, where `.SHELLFLAGS` is silently ignored).
- For this repo: `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test`, plus the WP0 accuracy check against the synthetic fixture set.

### 4.2 Tests
- **TDD**: every WP lists its first tests before its scope.
- **Mutation proofs** for gates and for the accuracy check: observe the test failing against a deliberate violation before trusting it. A passing test is not evidence by itself.
- **Seams before code**: time, randomness, filesystem, camera and model inference are ports from the first commit, so tests never need a device or real weights.

### 4.3 Working protocol
- One branch per WP (`wpN-<slug>`), off `main`. Worktrees under `.claude/worktrees/` when running agents in parallel; never bare `git stash` across worktrees.
- Each WP is implemented test-first by a subagent that does not proceed past a red gate.
- Each WP closes with **two parallel reviews against the diff**: (1) architecture conformance against the binding skills' own checklists, (2) code review for correctness, readability, security, performance. Findings go back to the implementer; reviews are not advisory.
- Decisions recorded as numbered entries in `.claude/wpN/NOTES.md` and stay binding until explicitly reversed.
- A `HANDOFF-WPn.md` at the end of each session: where the code is, what landed, what is left, what will bite, corrections to this plan, open judgement calls.

### 4.4 Binding skills (copy from `wegziel/.agents/skills/` and pin in `skills-lock.json`)
`flutter-apply-architecture-best-practices`, `flutter-add-widget-test`, `flutter-add-integration-test`,
`dart-add-unit-test`, `dart-run-static-analysis`, `dart-use-pattern-matching`, `dart-generate-test-mocks`,
`dart-use-ffigen` (only if ORT is bound via FFI), `test-driven-development`, `testability-seams`,
`incremental-implementation`, `error-handling-conventions`, `logging-strategy`, `spec-driven-development`,
`documentation-and-adrs`, `git-workflow-and-versioning`, `code-review-and-quality`.

The Go-, DDD- and backend-specific skills (`go-style`, `module-wiring`, `coordinate-boundary`, ...) do not apply.

---

## 5. Open questions for the first session

1. ~~Confirm or change P1 to P4.~~ Done (D8, D6).
2. ~~Final app name and bundle id.~~ Yomitanuki, `app.mcmaffin.yomitanuki` (D9).
3. ~~Model delivery for P2.~~ Bundled (D6).
4. ~~Dictionary scope for v1.~~ English only (D7).
