# WP0 — feasibility spike: decision log

Project root is `~/Documents/marv/manga_ocr` (the session was opened here, not in `~/Documents/marv/yomu`;
PLAN.md was copied over). Written 2026-10-13. Numbers below are from this Mac (Apple silicon, CPU
execution provider unless stated); they show relative cost only, the phone is measured in WP2.

## Decisions (binding until reversed)

- **D0.1 P1 confirmed: ONNX Runtime is the runtime.** Both models export to ONNX opset 17 and reproduce
  torch: the detector's final text blocks match 200/200 (IoU ≥ 0.7) on fp32 and fp16, the OCR encoder+
  hand-rolled greedy decoder matches torch's greedy token sequences exactly (10/10 crops checked token
  for token, preprocessing max abs diff 0.0). ORT 1.31 ships a CoreML execution provider for iOS.
- **D0.2 OCR decoding is plain greedy, no KV cache, no n-gram rule.** manga-ocr's own `generate()` runs
  4-beam search with `no_repeat_ngram_size=3` (from the model config). Against that reference, greedy
  scores CER 1.9 % / 92 % exact on 200 crops, and inspection shows most mismatches are greedy being right
  where the beam stutters (はっはっは vs はっほっは, １０年 vs １０９年) or the trigram rule truncating
  ellipses (．．． → ．．). The only collapses (text → "．．．．") are on false detections (a castle wall,
  smudges). Adding the trigram rule to greedy made it worse (90.5 % exact). The decoder has 2 layers,
  so recomputing the whole prefix each step costs 2–5 ms/step; a KV cache is not worth the Dart
  complexity.
- **D0.3 Quantisation: OCR int8 dynamic, detector fp16.** OCR int8 (ORT `quantize_dynamic`, QInt8
  weights) loses 0.4 pt CER (1.9 → 2.3 %) and is 2.4x faster; fp16 is bit-identical to fp32 on CPU.
  Detector int8 dynamic drops to 95.6 % precision / 97 % recall (dynamic quant does not quantise Conv
  well), so it is rejected; fp16 keeps 200/200 at half the size.
- **D0.4 Size budget: 165 MB of weights** (detector fp16 47.5 MB + OCR int8 116.6 MB), vs 556 MB fp32.
  P2 (weights outside the app build) stays recommended but is now optional: 165 MB is bundle-able if the
  Files-app import turns out annoying. Final call in WP1.
- **D0.5 Apply EXIF orientation before anything else.** mokuro 0.2.5 ignored the EXIF rotation of the
  iPhone photos (30 of 31 are stored landscape with orientation 6) and OCRed every page sideways; its
  `_ocr/*.json` output for this chapter is garbage and must not be used as reference. iOS camera
  frames and photo-library images need the same care in Dart (`image` package / platform decode).
- **D0.6 OCR input is the whole detected block, not mokuro's per-line crops.** manga-ocr was trained
  on bubbles; feeding the block crop with an 8 % margin gave clean text across 200 blocks, and it is
  what "tap a bubble" needs. Line splitting from mokuro is not ported.

## Numbers (200 blocks from 31 photos of Frieren vol. 1, local only)

| OCR variant (CPU EP) | CER vs beam ref | exact | size | median / p90 per block | encoder | decoder |
|---|---|---|---|---|---|---|
| fp32 greedy | 1.89 % | 92.0 % | 460.8 MB | 175 / 249 ms | 107 ms | 5.4 ms/step × 14.5 |
| int8 greedy | 2.29 % | 91.0 % | 116.6 MB | 73 / 104 ms | 44 ms | 2.1 ms/step × 14.6 |
| fp16 greedy | 1.89 % | 92.0 % | 230.7 MB | ≈ fp32 (fp16 is emulated on this CPU) | | |
| fp32 greedy + no-repeat-3gram | 1.89 % | 90.5 % | | | | |

| Detector variant | precision | recall | size | model ms / page (1024², Mac CPU) |
|---|---|---|---|---|
| torch fp32 (reference) | – | – | 79.9 MB .pt | ≈1000–1200 (full pipeline) |
| ONNX fp32 | 1.000 | 1.000 | 94.8 MB | ≈ 900–1350 |
| ONNX fp16 | 1.000 | 1.000 | 47.5 MB | ≈ same |
| ONNX int8 dynamic | 0.956 | 0.970 | 53.6 MB | ≈ 1100 |

Detector timings were taken while the OCR benchmark ran concurrently; treat them as ±30 %.

## What the Dart port has to reproduce (WP2 contract)

- Detector input: BGR→RGB, letterbox to 1024×1024 padding bottom/right with black, float32 /255, NCHW.
  Outputs: `blks (1,64512,7)` yolov5 raw [cx,cy,w,h,obj,cls×2], `mask (1,1,1024,1024)`,
  `lines (1,2,1024,1024)`. Post-processing (NMS conf 0.4 / IoU 0.35, DBNet line boxes, block grouping)
  is in `comic_text_detector/utils/` and is the biggest porting job; measure whether yolo NMS alone
  (blocks only, no lines/mask) is enough for "tap a bubble" before porting DBNet.
- OCR: grayscale→RGB, resize 224×224 bilinear, /255, (x−0.5)/0.5, NCHW; encoder → `(1,197,768)`;
  decoder takes `input_ids (1,L) int64` + `encoder_hidden_states`, returns `logits (1,L,6144)`; start
  token 2 ([CLS]), stop 3 ([SEP]), max 300; vocab is one character per token, no `##` pieces; skip ids
  0–4 and `<unusedN>`; then manga_ocr's `post_process` (strip whitespace, …→..., h2z ascii+digits).
  Reference implementation: `wp0/ocr_ort.py` (no transformers at runtime).

## Risks carried into WP2

- **CoreML EP coverage on this Mac was partial** (OCR fp32: 246 of 473 encoder nodes; fp16 graphs:
  only 14–25 nodes) and not faster than CPU here. On iPhone the CPU numbers alone should still be well
  under a second per bubble, but the first WP2 task is an on-device timing with `MLProgram` format and
  ORT's transformer optimiser, before anything is built on top.
- The `generate()` reference includes `early_stopping`, `length_penalty 2.0` and beam search; none of
  it is ported, by D0.2.
- fp16 detector on CPU EP in ORT inserts casts; on-device speed may differ from fp32. Keep both files
  until WP2 measures.

## Open questions for Marv (from PLAN §5, unchanged)

P2 (model delivery), P3 (deinflection + longest match), P4 (synthetic CI fixtures) are untouched by
WP0 and still need a yes. Name, bundle id, dictionary language scope (JMdict has German glosses) too.
