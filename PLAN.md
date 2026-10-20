# yomu: plan and locked decisions

Working name (読む, "to read"). Rename freely before WP1.

A personal Flutter app for reading **physical** manga with instant lookups: point the camera at a
page, the app boxes the speech bubbles live, tap one, get the text, tap a word, get the dictionary
entry, one tap adds it to Anki. Everything runs on the phone. (Name: Yomitanuki, D9.)

Written 2026-10-13. This file is the project's decision record: the locked decisions D1 to D10,
the proposals they resolved, and the work packages.

---

## 0. Locked decisions

| # | Decision | Locked | Why |
|---|---|---|---|
| D1 | Flutter | 2026-10-13 | Android support wanted eventually. iOS is the only v1 target. |
| D2 | Fully on device | 2026-10-13 | No server, no network dependency while reading. |
| D3 | Automatic bubble detection from the start | 2026-10-13 | Tap a bubble instead of dragging a crop box. |
| D4 | iOS only for v1 | 2026-10-13 | Android is a later work package, not a v1 constraint. |
| D5 | wegziel's engineering practices apply | 2026-10-13 | See §4. |
| D6 | Model weights ship **inside the app bundle** (replaces P2) | 2026-10-13 | WP0 cut the weights to 145 MB (live detector fp32 28 MB + OCR int8 117 MB; C8); the simpler build was preferred over a Files-app import. Weights are rebuilt deterministically by a `make models` recipe, never committed. |
| D7 | Dictionary glosses in English only for v1 | 2026-10-13 | German can be added later from the same JMdict build. |
| D8 | P1, P3, P4 confirmed | 2026-10-13 | P1 by WP0 measurement (`.claude/wp0/NOTES.md`), P3 and P4 accepted without change. |
| D9 | App name **Yomitanuki** (読みたぬき), bundle id `app.mcmaffin.yomitanuki` | 2026-10-13 | Yomitan + tanuki, the Shigaraki statue that holds an account book. |
| D10 | **Live detection is the target UX**: bubbles are boxed on the camera stream at ~1 Hz (D0.13), tapping one OCRs it. No tap-anywhere fallback, no full-model still path in v1 (D0.11). A still photo is the fallback path, not the design centre. | 2026-10-13 | The dynamic case is the target; the reader holds the camera steady. WP2 measures one detection pass end to end on device; WP4 is built around the camera image stream. |

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

- A local `mokuro` checkout's `.venv` already has `manga_ocr`, torch and fugashi installed. WP0 can start from it.
- The `wegziel` repo is the reference for process and gates (§4).
- `learning_tool` is a separate earlier project; not part of this.

---

## 3. Work packages

Status 2026-10-14: WP0, WP0b, WP1, WP2 (a: binding, b: adapters; task 1 on-device timing still
open), WP3, WP4, WP5 are merged on `main`, each reviewed.

Each WP names its first tests before its scope. A WP is done when `make gate` is green and both
reviews in §4.3 are clean.

### WP0: feasibility spike (Python, no app code)
The riskiest part is the manga-ocr decoder export, so it is proven before any UI exists.
- Export comic-text-detector to ONNX (or use the published ONNX file) and run it in Python with `onnxruntime`.
- Export manga-ocr with `optimum` (encoder and decoder as separate graphs). Reimplement the greedy decode loop by hand against ORT, outside `transformers`, because that loop is what Dart has to reproduce.
- Quantise (dynamic int8 for the decoder, fp16 for the encoder as a first try).
- Measure on ~30 bubbles from my own photos: **character error rate fp32 vs quantised**, latency, file sizes.
- **Exit:** numbers recorded in `.claude/wp0/NOTES.md`, P1 confirmed or rejected, size budget decided.

### WP0b: make the graphs the contract (Python, after the review of WP0)
- Bake preprocessing into both ONNX graphs (uint8 image in: grayscale, antialiased resize, normalise;
  letterbox for the detector) so Dart does no pixel loops and the graph is the contract (D0.9, C1, C2).
- Commit **synthetic goldens** (rendered-text crops and rendered pages, so nothing from a book):
  per crop the PNG (or raw padded BGRA rows), full id sequence and final text; per page the PNG and the
  post-NMS boxes; every golden carries the sha256 of the graphs it was recorded with. (Amended by WP0b:
  no input-tensor / encoder-output hashes, the preprocessing lives inside the graphs and int8 encoder
  outputs are not bit-stable across execution providers; see D0b.8.) These are WP2's first red tests.
- `make models`: deterministic re-export + quantisation from the pinned venv (C8).
- Score beam / greedy / int8 against hand-transcribed ground truth once the author has transcribed ~50
  bubbles (C6); add ~20 horizontal/SFX/number crops to the private set.
- **Exit:** goldens in git, `.claude/wp0/NOTES.md` contract section rewritten against the new graphs.

### WP1: scaffold and gate
- `flutter create`, iOS only enabled. Strict analysis (flutter_lints plus stricter rules, `--fatal-infos`).
- `Makefile` with `make gate` == `.github/workflows/ci.yml`, line for line (§4.1).
- Layering per `flutter-apply-architecture-best-practices`: `ui/<feature>/{view, view_model}`, `domain/models`, `data/{services, repositories}`.
- First tests: a gate mutation proof (a deliberately unformatted / lint-violating fixture must turn the gate red).

### WP2: inference core behind ports
- **Task 0: the ORT binding.** Expected: a thin `ffigen` binding against the `onnxruntime-c` pod
  (C13); it must expose the CoreML options in D0.10 and provide a macOS dylib so `flutter test` can
  run real inference for the accuracy gate. Decide and record before any adapter code.
- **Task 1, gating (D10): end-to-end on-device timing**, frame arrives → boxes drawn, with per-stage
  timings (frame copy, rotation, tensor, `run`, NMS, tracking) at the 1080p stream preset (D0.12),
  blocks-only fp32 on CoreML NeuralNetwork/ANE (D0.10) and on CPU, 640 and 1024. Target: one
  detection pass well under a second, one OCR pass under about a second (D0.13: ~1 Hz sampling, OCR
  on tap only). Memory (C4) is recorded in the same run. Needs the iPhone connected; until then the
  simulator only proves linking.
- Ports: `TextDetector`, `OcrEngine`. ORT adapters implement them; fakes implement them for every other test.
- Image preprocessing (resize, normalise, crop from detected box) as pure Dart, unit tested.
- Decoder loop in Dart, tested against the WP0b synthetic goldens (same input → same tokens).
- Detector post-processing per C10 (NMS only; the mask/DBNet branch is not ported in v1, D0.11).
- Inference runs off the UI isolate.
- First tests: preprocessing golden values; decode-loop parity with WP0; synthetic-image OCR returns the rendered string.

### WP3: dictionary
- Build script: jmdict-simplified + KANJIDIC2 → SQLite asset, with an indexed reading/kanji lookup.
- Deinflector + longest match **starting at the tapped character** (C15); no whole-line pre-segmentation.
- First tests: a conjugation table (食べられなかった → 食べる, 行って → 行く, 強そう → 強い, 来るはず → 来る + はず, 知っています → 知る), plus segmentation of whole lines.

### WP4: capture and reader UI
- Live camera stream (D10): detector runs on downscaled frames off the UI isolate, boxes are drawn
  over the preview; tapping a box OCRs the crop from the current 1080p stream frame (D0.12);
  detection samples ~1 frame/s (D0.13). ~~Boxes tracked between frames~~: at 1 Hz there is
  nothing to track between, the boxes are simply redrawn per sample (WP4 D4.15). The capture
  session must resume cleanly after AnkiMobile foregrounds (C14). Photo picker and page view
  with zoom as the fallback path.
- Tap block → OCR text with each word tappable → lookup popup (reading, meanings, kanji breakdown).
- Widget tests with fake ports; one integration test on simulator with a synthetic page.

### WP5: Anki export
- Build the `addnote` URL from a lookup result + context line; deck and note type configurable;
  `dupes` handling decided explicitly, `LSApplicationQueriesSchemes`, percent-encoded names (C14).
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
- Decisions and leftovers (what is left, what will bite, corrections to this plan, open judgement calls) are recorded in `.claude/wpN/NOTES.md`; there is no separate handoff file.

### 4.4 Binding skills (copy from `wegziel/.agents/skills/` and pin in `skills-lock.json`)
`flutter-apply-architecture-best-practices`, `flutter-add-widget-test`, `flutter-add-integration-test`,
`dart-add-unit-test`, `dart-run-static-analysis`, `dart-use-pattern-matching`, `dart-generate-test-mocks`,
`dart-use-ffigen` (ORT is bound via FFI, WP2 task 0), `test-driven-development`, `testability-seams`,
`incremental-implementation`, `error-handling-conventions`, `logging-strategy`, `spec-driven-development`,
`documentation-and-adrs`, `git-workflow-and-versioning`, `code-review-and-quality`.

The Go-, DDD- and backend-specific skills (`go-style`, `module-wiring`, `coordinate-boundary`, ...) do not apply.

---

## 5. Open questions for the first session

1. ~~Confirm or change P1 to P4.~~ Done (D8, D6).
2. ~~Final app name and bundle id.~~ Yomitanuki, `app.mcmaffin.yomitanuki` (D9).
3. ~~Model delivery for P2.~~ Bundled (D6).
4. ~~Dictionary scope for v1.~~ English only (D7).
