# Handoff after WP0 (2026-10-13)

**Where the code is:** `~/Documents/marv/manga_ocr`, branch `main`, two commits. (`~/Documents/marv/yomu`
only holds the original PLAN.md; this folder is the project.)

**What landed:** WP0 complete. ONNX exports of both models, a transformers-free greedy OCR pipeline
(`wp0/ocr_ort.py`), quantised variants, parity and benchmark scripts, decisions D0.1–D0.6 and all
numbers in `.claude/wp0/NOTES.md`. Exit criteria met: P1 confirmed, size budget 165 MB.

**Local-only artefacts (gitignored):** `wp0/models/` (ONNX files, ~1 GB in all variants),
`wp0/fixtures/private/` (200 block crops + reference text from the 31 Frieren photos in
`~/Downloads/frieren_ch01`), `wp0/results/`. Rebuild with the commands in `wp0/README.md`.

**What is left:** WP1 onwards. WP1 needs the answers below first.

**What will bite:**
- CoreML execution-provider coverage was partial on the Mac; measure on the phone before building on it.
- EXIF orientation: apply it to every camera/photo input (D0.5).
- The detector's post-processing (NMS, DBNet lines, block grouping) is the largest porting job; check
  whether yolo blocks + NMS alone suffice for tapping bubbles before porting the line/mask path.
- GPL-3.0 on comic-text-detector and Yomitan's deinflection rules: fine privately, check before distributing.

**Corrections to PLAN.md:** none to the decisions. §2's "mokuro output as reference" idea is dead
(mokuro ignored EXIF, its JSON is garbage); the fp32 beam output on correctly rotated crops is the
reference instead. The per-WP reviews (§4.3) were not run for WP0: it is a spike with no app code.

**Open judgement calls for Marv:** P2, P3, P4 (unchanged from PLAN §5), the app name and bundle id,
dictionary language scope, and whether 165 MB of weights go into the bundle after all.
