# Handoff, session of 2026-10-13/14

**Where the code is:** `~/Documents/marv/manga_ocr`, branch `main`, 111 commits, gate green
(`make gate`: format, analyze `--fatal-infos`, 366 app tests + 33 binding tests, four-step mutation
proof, simulator debug build and unsigned release device build with the ORT symbol verified).
Flutter app in `app/` (≈6 000 lines of Dart, ≈6 900 of tests), ORT binding in
`app/packages/ort_ffi/`, Python spike and graph builder in `wp0/`, dictionary builder in
`tool/dict/`. Earlier per-package handoffs: `HANDOFF-WP0.md`, `HANDOFF-WP1.md`.

## What landed, by work package (all merged into main, each reviewed, findings fixed)

| WP | Branch | What | Decisions |
|---|---|---|---|
| WP0 | main | ONNX feasibility, P1 confirmed; adversarial review folded in (C1–C15) | `.claude/wp0/NOTES.md` D0.1–D0.13 |
| WP0b | wp0b-graph-contract | Preprocessing + NMS baked into the graphs (BGRA in, blocks out); 18 synthetic goldens; `make models` | D0b.1–D0b.8 |
| WP1 | wp1-scaffold | Scaffold, strict analysis, `make gate == ci.yml`, mutation proof, 17 skills pinned | `.claude/wp1/NOTES.md` D1.1–D1.14 |
| WP2a | wp2a-ort-binding | `ort_ffi`: ffigen binding of ORT 1.31 C API, CoreML options, iOS pod 1.30, macOS dylib for tests | `.claude/wp2/NOTES.md` D2.1–D2.12 |
| WP2b | wp2b-ort-adapters | Worker isolates, `OrtTextDetector`, `OrtOcrEngine`, greedy decoder, `post_process` port, `ModelAssets`, lazy wiring | D2.13–D2.25 |
| WP3 | wp3-dictionary | JMdict+KANJIDIC2 → SQLite (56 MB, `make dict`), own deinflection table, tap-position lookup | `.claude/wp3/NOTES.md` D3.1–D3.10 |
| WP4 | wp4-reader-ui | Live reader: camera stream adapter, 1 Hz sampling, overlays, OCR sheet, lookup cards, photo path with zoom, about screen | `.claude/wp4/NOTES.md` D4.1–D4.18 |
| WP5 | wp5-anki | `addnote` URL exporter (HTML-escaped), settings screen + persistence, note builder | `.claude/wp5/NOTES.md` D5.1–D5.8 |

Harness: `CLAUDE.md`/`AGENTS.md`, bulk-read guard hook, subagent model judge, builder and
bulk-reader agents (ported from al-backend; active from the next session).

## Verified end to end (simulator, real adapters)

`app/integration_test/real_pipeline_test.dart`: a page rendered with dart:ui, one bubble with
vertical 魔王を倒した勇者, fed as a frame → the ONNX detector boxes it → tap → OCR reads it → tap 魔 →
the bundled dictionary shows 魔王 まおう "demon lord" → Add to Anki builds the note. Passed on the
iPhone 16 simulator in 5 s including the first-run model copy. `make gate-integration` runs it and
the fake-port flow (not in `make gate`: needs a booted simulator).

Timings on the M2 (`--concurrency=1`): detector 32 ms/page on CoreML (ANE), 157 ms on CPU;
OCR 56–85 ms per bubble on CPU. Dictionary lookup 0.4 ms.

## What needs Marv (in order)

1. **First run on the iPhone** (WP2 task 1, `.claude/wp2/NOTES.md` D2.23 is the checklist): plug
   in, `make models && make dict` if not done, `cd app && flutter run --release -d <phone>`
   (signing identity in Xcode, Developer Mode on the phone). Verify: the ORT symbol lookup in a
   release build, the first-launch asset copy (145 MB models + 56 MB dictionary), the CoreML
   partition count, per-stage timings at 1080p, memory, the camera rotation direction (D4.3,
   unverified in the simulator), the AnkiMobile round trip (the `anki://` scheme only exists on the
   phone), and the camera permission prompt flow.
2. **Ground truth** (C6): correct `wp0/fixtures/private/ground_truth.json` using the five
   contact sheets `wp0/fixtures/private/ground_truth_sheet_*.png` (50 bubbles, prefilled with the
   model's reading; set `verified: true` per entry), then `wp0/.venv/bin/python
   wp0/score_ground_truth.py` gives real CER for beam, greedy and int8. The first sheet already
   shows greedy beating the beam reference on ellipses and はっはっは.
3. **Real-manga check** with the app: hold the phone over Frieren; the live path is the whole
   point and has only been exercised with synthetic pages.

## What will bite

- **CI has never run** (no remote). First push: `subosito/flutter-action` honouring
  `flutter-version-file`, `astral-sh/setup-uv`, `make models` downloading the HF weights and the
  comic-text-detector `.pt` (≈530 MB) on the runner within the 45-minute timeout, `make dict`
  is NOT in CI (the dictionary tests use the committed mini fixture), the simulator build on
  `macos-15`.
- **A debug build launched outside `flutter run` shows a white screen** on the simulator
  (observed; a Flutter debug-mode quirk, not seen under `flutter run`). Use `flutter run` or a
  release/profile build on the phone.
- The `onnxruntime-c` pod is 1.30 against 1.31 bindings (API version 30 requested; D2.4). Bump
  both when the pod catches up.
- `camera` on iOS: the stream frames arrive in display orientation per the plugin source
  (D4.3); if boxes appear rotated on device, `orientForPortrait` in
  `lib/data/services/camera/frame_orientation.dart` is the one place to fix.
- Generated code is excluded only inside `ort_ffi`; the app itself has no code generators
  (by decision, D1.x/WP2–WP5): keep it that way or add analyzer excludes first.
- `make gate` now takes several minutes (two iOS builds) and needs the network once (ORT dylib,
  Python venv). `make gate-integration` additionally needs a booted simulator.
- Memory on 4 GB phones: live detector + OCR ≈ 360 MB RSS on the Mac; the full three-head
  detector is deliberately not shipped (C4, D0.11).

## WP6 polish list (from the reviews and the UX self-assessment, `.claude/wp4/NOTES.md`)

Crop thumbnail at the top of the OCR sheet (the sheet hides the bubble), bottom-reachable actions
for one-handed use, swipe-down to close the sheet, inline retry on OCR/lookup failure, larger
character cells, vertical text / furigana rendering, a Settings deep link from the permission
card, copula deinflection (静かだった, D3.10), a per-form matched reading in the dictionary
(ビール shows 麦酒's reading today), deep-link parsing of `yomitanuki://anki-return`, SHA-pinned
GitHub actions, `flutter_onnxruntime`-style zero-copy frames if device timings demand it.

## Corrections to PLAN.md made this session

D6 (bundle weights), D7 (English only), D8 (P1/P3/P4 confirmed), D9 (name), D10 (live UX),
D0.11–D0.13 (no fallback, 1080p crops, ~1 Hz), WP0b inserted, WP2 task 0/1 rewritten, WP3 tap-
position lookup, WP4 tracking struck (D4.15), WP5 Anki details. Reviews per WP were one combined
review for the small packages (WP0b, WP2a, WP3, WP5) and two for the large ones (WP4, WP1), a
deviation from §4.3's "two parallel reviews" that bought time, not rigour.
