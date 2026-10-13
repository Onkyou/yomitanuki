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

## Addendum 2026-10-13: live detection (D10)

- **D0.7 The live path uses a blocks-only detector: the yolov5 head alone, fp32 ONNX, CoreML EP.**
  Exported without the UNet mask and DBNet line branches it is 28 MB and the CoreML execution
  provider takes the whole graph. On this Mac that gives 18 ms/frame at 1024² and 7 ms at 640² (vs
  151 / 62 ms on CPU and ~1 s for the full three-head model). The iPhone's Neural Engine is in the same
  class, so 20+ fps of box detection on a camera stream is realistic; WP2's first task measures it.
- **D0.8 Ship fp32 ONNX files for anything that should run on CoreML.** The fp16-converted graphs
  carry Cast nodes that break CoreML partitioning (154 ms instead of 18 ms for the same network). CoreML
  runs fp16 internally anyway. fp16 files are only a size optimisation for CPU-bound graphs; this
  reverses the "detector fp16" half of D0.3 for the live detector (28 MB fp32 is small enough).
- Blocks-only recall against the full-pipeline reference blocks (IoU ≥ 0.5, 200 blocks, 31 pages):
  86.5 % at 1024 (precision 94 %), 81.5 % at 640 (92 %). The missing blocks are ones the full pipeline
  derives from the DBNet line map; across consecutive frames the live view will recover some, and a
  still-photo pass with the full model stays available for the rest. Whether the full model is worth
  porting at all is decided in WP2 after measuring on device.
- Script: `wp0/live_detector.py` → `results/live_detector.json`.

## Review corrections 2026-10-13 (adversarial review of plan + WP0; re-measured on Apple M2 4P+4E, 16 GB, ORT 1.31, default threads)

Corrections to statements above. Where a correction changes a decision, the new decision is numbered.

- **C1 The detector input is BGR, not RGB.** `preprocess_img` converts BGR→RGB and then flips the
  channel axis back (`transpose(2,0,1)[::-1]`), so the tensor the network sees is B,G,R (verified:
  tensor channel 0 equals source B exactly). The "BGR→RGB" line in the porting contract was wrong.
- **C2 "Resize 224×224 bilinear" is under-specified.** PIL's BILINEAR is antialiased when downscaling
  (crops are 2–4× larger than 224). A non-antialiased bilinear (cv2 INTER_LINEAR, `package:image`'s
  linear) changes the token sequence on 9 of 200 crops. The grey conversion is not the hazard.
  **D0.9 Preprocessing is baked into the ONNX graphs** (uint8 image in; grayscale, antialiased resize,
  normalise, letterbox inside the graph) so that the graph, not `ocr_ort.py`, is the contract and Dart
  does no pixel loops. Work item: WP0b.
- **C3 CoreML provider options matter and MLProgram is the wrong one.** Blocks-only 1024 fp32:
  CoreML NeuralNetwork format 17.4 ms (ANE); MLProgram 27 ms (that is the GPU) and MLProgram +
  CPUAndNeuralEngine 111 ms (never reaches the ANE); MLProgram fails to compile the OCR encoder.
  **D0.10 CoreML sessions are created with `ModelFormat=NeuralNetwork`, `MLComputeUnits=
  CPUAndNeuralEngine` (so a GPU fallback cannot mask an ANE rejection) and a `ModelCacheDirectory`**
  (compile took 1.8 s per session on M2). The earlier "MLProgram" advice is withdrawn.
- **C4 Memory.** Max RSS: blocks-only fp32 on CoreML + OCR int8 ≈ 360 MB total; the full three-head
  detector at 1024² on CPU adds ~0.9 GB (UNet activations), i.e. ~1.25 GB, which is jetsam territory
  on 4 GB iPhones. A full-model still path, if it exists at all, runs at ≤ 768² or on CoreML.
- **C5 Blocks-only recall has a ceiling of ~92 %.** Conf sweep at 1024 (recall/precision vs the
  200 full-pipeline blocks, IoU ≥ 0.5): 0.4 → 86.5/94.0, 0.2 → 89.5/91.8, 0.05 → 92.0/84.8. About 8 %
  of blocks come only from the mask/DBNet branch; frame jitter will not create them. The earlier
  "consecutive frames will recover some" was unsupported and is withdrawn.
  **D0.11 (confirmed by Marv 2026-10-13): v1 runs blocks-only at conf 0.2 (~90 % of bubbles
  boxed); no tap-anywhere fallback; the full model is not ported in v1.** Conf is a tunable in the
  port.
- **C6 The accuracy numbers are agreement-with-beam, not accuracy.** The reference is the same
  model's 4-beam output; "greedy is right where the beam stutters" was judged by eye on 16 crops; the
  int8 "cost" (18 vs 16 differing crops of 200) is within noise. Fixtures are 197/200 vertical
  dialogue from one volume, one phone, one lighting. Needed: ~50 hand-transcribed bubbles
  (`fixtures/private/ground_truth.json`, a human task) plus ~20 horizontal/SFX/number crops; then
  CER for beam, greedy and int8 against ground truth sets the accuracy-gate threshold.
- **C7 Stream resolution matters for OCR.** Crops downscaled to what a page filling a camera frame
  gives (fp32 greedy, exact-vs-beam): 3024 px wide 92.0 %, 1920 px 90.5 %, 1280 px 90.5 %, 960 px
  85.0 %. Median bubble is 189 px wide in a 12 MP photo, ~80 px at 720p. The `camera` plugin's image
  stream runs at the preview preset and its own docs recommend a low preset for streaming; full
  resolution only comes from `takePicture()` (0.3–1 s, different aspect ratio and exposure).
  **D0.12 (confirmed by Marv): OCR crops come from a 1080p camera stream frame, no `takePicture` path in v1;**
  WP2's on-device gate must include the frame-copy cost at that preset. Motion blur is unmeasured.
- **C8 Size budget is 145 MB, not 165:** live detector fp32 28.2 MB (D0.8) + OCR int8 116.6 MB. A
  full-model still path would add 94.8 MB. D6 updated in PLAN.md. Weights need a CI source: the
  README's `optimum-cli` export is byte-identical on re-run, so a `make models` recipe that re-exports
  from the pinned venv is a legitimate deterministic source (check `quantize_dynamic` likewise).
- **C9 Which numbers transfer to an iPhone.** Transfer: file sizes, token parity (now verified on
  200/200 crops), agreement rates (if preprocessing bit-matches, D0.9), the recall ceiling, CPU ≫
  CoreML-NN ordering for the small conv net. With caveats: 17 ms blocks-only on ANE (NeuralNetwork
  format only; partitioning and throttling may differ). Do not transfer: every CPU latency (expect
  2–3× slower on 2P+4E, so ~200–300 ms per bubble for int8 OCR, still fine), the 27 ms GPU number,
  "fp16 identical" (CPU emulation; the one real fp16 run, full detector on CoreML, gave 199/200), and
  all latencies in `results/ocr.json` (contended; `time_ocr.py` numbers are the clean ones).
- **C10 Detector post-processing contract, precisely:** letterbox `new = round(shape·r)`,
  `cv2.INTER_LINEAR` (not antialiased), pad right/bottom black; NMS: candidates by `obj > 0.4`, then
  `conf = obj × cls` best class only, filter `conf > 0.4` again, class-aware NMS (box offset
  class×4096), IoU 0.35, `max_det` 300; boxes xyxy in letterbox space scaled by
  `(W/(size−dw), H/(size−dh))` then truncated to int. Blocks-only graph output is `(64512,7)`.
- **C11** `detokenise` drops `<unusedN>` tokens where `tokenizer.decode` would emit them literally;
  none of the 200 crops emits one. Better behaviour, but not parity; stated here.
- **C12** The WP2 gate "≥ 5 fps" must be measured end to end (frame arrives → boxes drawn) with
  per-stage timings, not as `sess.run` time: frame delivery on the UI isolate, BGRA→tensor,
  rotation (stream frames arrive in sensor orientation; D0.5 only covered EXIF on photos), NMS over
  64 512 rows and box tracking are each 10–80 ms in pure Dart.
- **C13** The ORT↔Flutter binding is a decision, not an "only if": pub.dev plugins are platform-
  channel based (a 12 MB tensor copy per frame) or old FFI forks, and none exposes the CoreML options
  in D0.10. Expected route: a thin ffigen binding against the `onnxruntime-c` pod. It also determines
  the macOS dylib needed for any `flutter test` that runs real inference. Moved to WP2 task 0.
- **C14 Anki:** `addnote` refuses a duplicate first field unless `dupes=1`; every add foregrounds
  AnkiMobile, which tears down the capture session, so the live loop must resume on return; iOS needs
  `LSApplicationQueriesSchemes: [anki]`; the note type name must be percent-encoded.
- **C15 WP3:** longest-match segmentation of a whole kana-heavy line will mis-split; Yomitan's
  primitive is "longest match starting at the tapped character". The word-tappable UI scans from the
  tap position instead of rendering a pre-split line.
- Sound (checked by the reviewer, listed so it is known): greedy loop and n-gram ban equal
  transformers on 200/200; detokenise+post_process equals `tokenizer.decode` on 200/200;
  `preprocess()` equals `ViTImageProcessor` to 0.0 on 200/200; letterbox side and ratio; the
  optimum export is reproducible byte for byte; D0.5, D0.6 and the no-KV-cache trade are sound.

- **D0.13 (Marv, 2026-10-13): detection runs at ~1 Hz, not per frame; OCR runs only on tap.** He
  holds the camera steady. The live loop samples one stream frame per second (tunable), detects,
  redraws the boxes; frames in between are dropped. This replaces the "≥ 5 fps" gate: WP2's
  on-device measurement must show one detection pass (frame → boxes drawn) well under a second,
  and one OCR pass under about a second, and records memory. The CoreML/ANE path remains the
  target, but a CPU-only fallback is now acceptable for detection too.
