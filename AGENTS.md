# AGENTS.md

The single source of truth for how to work in this repo. **Skills carry the rules**: this
file is overview and pointers; read the skill named for your area before touching code.
Skills live in `.agents/skills/` (pinned in `skills-lock.json`); `CLAUDE.md` imports this
file and adds Claude Code specifics.

Yomitanuki is a personal Flutter iOS app: point the camera at a physical manga page, bubbles
are boxed live, tap one to OCR it on device, tap a word for the JMdict entry, one tap to Anki.
No server, no network while reading. Decisions D1–D10 in `PLAN.md` are locked; per-work-package
decisions live in `.claude/wpN/NOTES.md` and stay binding until explicitly reversed.

## Commands

```bash
make gate            # the merge gate (== .github/workflows/ci.yml, line for line) — do NOT retype it
make help            # every target with a one-line description
make models          # rebuild app/assets/models/ (gitignored ONNX graphs, D6) from the pinned wp0/.venv
make models-check    # run the built graphs against the synthetic goldens in app/test/goldens/
```

`make models` creates `wp0/.venv` with uv if it is missing and skips the build when
`app/assets/models/manifest.json` is newer than `wp0/build_graphs.py` and the lock file. The graphs
are the inference contract (D0.9): BGRA uint8 in, boxes / hidden states out, see `.claude/wp0/NOTES.md`.

The Makefile exists because hand-copied gate commands drift. `make gate` runs
`dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test`, the
gate mutation proof and the iOS build (simulator debug, unsigned device release, each checked
for the ONNX Runtime symbol) over the whole tree, with no baseline. A gate that only exists in CI is
found after a push; one that only exists locally gets skipped.

⚠️ Do not end a gate command with `; echo "exit=$?"` or `| tail`: the shell then reports the
last command's status, and a failed gate reads as 0. Let `make` be last.

## How we work

Spec → plan → build test-first → two adversarial reviews, then merge when both are clean.

- **Spec / plan**: `spec-driven-development`, `planning-and-task-breakdown`; stress-test a
  decision with `doubt-driven-development` before it stands.
- **Build**: `test-driven-development` (name the first tests before the scope; watch a gate go
  red before trusting it), `incremental-implementation`, `testability-seams` (camera, model
  inference, files, time and randomness are ports from the first commit).
- **Review**: each work package closes with two parallel reviews of the diff, architecture
  conformance against the skills' checklists and a correctness/readability/security/performance
  review. Findings go back to the implementer; reviews are not advisory.
- **Branches**: one per work package, `wpN-<slug>` off `main`; worktrees under
  `.claude/worktrees/` for parallel agents; never a bare `git stash` across worktrees.

## Architecture (read the skill before touching the area)

Flutter app in `app/`, layered per `flutter-apply-architecture-best-practices`:
`lib/ui/<feature>/{view,view_model}`, `lib/domain/models`, `lib/data/{services,repositories}`.
Inference (`TextDetector`, `OcrEngine`) and the camera are **ports**; ONNX Runtime adapters
implement them, fakes implement them in every other test. Inference never runs on the UI isolate.

- **Models**: ONNX, shipped inside the bundle (D6). The WP0 contract the Dart port must
  reproduce (preprocessing, greedy decode loop, detokenisation) is in `.claude/wp0/NOTES.md`
  with the reference implementation in `wp0/ocr_ort.py`. Apply EXIF orientation to every
  camera frame and photo before anything else (D0.5).
- **Dictionary**: JMdict + KANJIDIC2 as SQLite, English glosses (D7); deinflection + longest
  match in pure Dart (P3). EDRDG attribution screen required.
- **Anki**: AnkiMobile URL scheme, deck and note type configurable.
- **Static analysis**: `dart-run-static-analysis`; the gate runs with `--fatal-infos`.
- **Errors**: expected failures are `Exception` subtypes (`lib/domain/errors.dart`, the adapters'
  own types) caught with `on Exception`; an `Error` (`NotWiredError`, `ArgumentError`) is a bug and
  is never caught, except at the reader's port boundary, which maps anything a port throws to a message.
- **Logging**: `developer.log` with a `name` per area (`reader`, `camera`, `capture`, `settings`);
  no `print`/`debugPrint`. `flutter run --profile` shows the logs, `--release` hides them.

## Things that will cost you if skipped

- Photos of book pages, OCRed book text and model weights never enter git (P4, `.gitignore`).
- The WP0 Python spike in `wp0/` is reference material, not app code; do not "clean it up".
- The comic-text-detector weights are GPL-3.0 and so is this repository (`LICENSE`); the
  deinflection table is the repo's own, no Yomitan code is used. Keep it that way, or the
  licence has to change.
