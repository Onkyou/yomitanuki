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

## What the Dart port has to reproduce (WP2 contract; rewritten by WP0b against the built graphs)

Three graphs in `app/assets/models/` (built by `make models` from the pinned `wp0/.venv`, gitignored,
D6; `manifest.json` carries sha256, sizes, opsets and this contract machine-readably). Every graph takes
the raw camera/photo layout: **`image` uint8 `[1,H,W,4]` BGRA, row-major, tightly packed**
(`BgraImage` with `bytesPerRow == width*4`; repack when the buffer has row padding, `crop()` already
does), any H ≥ 1 and W ≥ 1 (a side thinner than 1/2048 of the other is letterboxed to 1 px by an
in-graph `Max`, so 4096×1 runs). EXIF orientation / sensor rotation is applied before the graph (D0.5,
C12). Dart does **no pixel loops and no NMS** (D0.9, C12); reference runner `wp0/app_graphs.py`.

- **`detector.onnx`** (opset 17, fp32, 28.2 MB). Inputs `image` and `conf_threshold` float32 `[1]`,
  **0 ≤ conf_threshold ≤ 1** (clipped in-graph; a negative value would otherwise admit the zero-scored
  other-class NMS entries; app default 0.2, D0.11; a tunable). Output `blocks` float32 `[N,5]` = x0,y0,x1,y1,score in **input
  pixel coordinates**, xyxy, score descending, **not clipped** to the image (clamp when cropping), N may
  be 0. Inside: alpha dropped, B,G,R kept (C1); letterbox r=min(1024/H,1024/W), new=round(shape·r)
  (half to even), bilinear half-pixel, zero pad right/bottom, /255 (C10); blocks-only yolov5 head
  (D0.7); xywh→xyxy; conf=obj·max(cls), best class; class-aware `NonMaxSuppression` IoU 0.35,
  ≤300 per class, keep score > conf_threshold; boxes scaled by (W/new_w, H/new_h). The 8 % OCR crop
  margin (D0.6) is added in Dart.
- **`ocr_encoder.onnx`** (opset 18, int8 dynamic weights, preprocessing stays uint8/float, 87.0 MB).
  Input `image` (the crop). Output `encoder_hidden_states` float32 `[1,197,768]`. Inside: PIL-exact
  grey `(19595·R + 38470·G + 7471·B + 32768) >> 16`, antialiased bilinear `Resize` to 224×224 on uint8
  (Resize-18, antialias=1, half-pixel), /255, (x−0.5)/0.5, grey replicated to 3 channels, NCHW, ViT.
- **`ocr_decoder.onnx`** (opset 17, int8, 29.6 MB). `input_ids` int64 `[1,L]` + `encoder_hidden_states`
  → `logits` float32 `[1,L,6144]`. The optimum export, unchanged.
- **What stays in Dart** (the only inference logic outside the graphs): the greedy loop, ids=[2];
  each step runs the decoder on the whole prefix (no KV cache, D0.2), next=argmax(logits[0,−1]),
  append, stop at 3 or 300 tokens; the first generated token is 2 again, that is normal. Detokenise:
  skip ids 0–4 and tokens starting with `<unused`, join `vocab.txt` lines (one character per token,
  no `##` pieces), then manga_ocr's post_process: strip whitespace, `…`→`...`, every run of `[・.]{2,}`
  → the same number of `.`, `jaconv.h2z(ascii=True, digit=True)` (ASCII and digits to full width).
- **Session options**: detector on the CoreML EP with D0.10 (`ModelFormat=NeuralNetwork`,
  `MLComputeUnits=CPUAndNeuralEngine`, `ModelCacheDirectory`) **plus `RequireStaticInputShapes=1`
  (D0b.6, mandatory)**; both OCR graphs on the CPU EP (int8 ops have no CoreML kernels).
- **Goldens** (WP2's first red tests): `app/test/goldens/ocr/*.{png,json}` (token ids exact, text
  exact) and `app/test/goldens/detector/page_01.{png,json}` (same block count, each block within ±2 px
  per coordinate and ±0.02 score); `wp0/check_goldens.py` (`make models-check`) is the reference checker.

## Risks carried into WP2

- **CoreML EP coverage on this Mac was partial** (OCR fp32: 246 of 473 encoder nodes; fp16 graphs:
  only 14–25 nodes) and not faster than CPU here. On iPhone the CPU numbers alone should still be well
  under a second per bubble, but the first WP2 task is an on-device timing with `MLProgram` format and
  ORT's transformer optimiser, before anything is built on top.
- The `generate()` reference includes `early_stopping`, `length_penalty 2.0` and beam search; none of
  it is ported, by D0.2.
- fp16 detector on CPU EP in ORT inserts casts; on-device speed may differ from fp32. Keep both files
  until WP2 measures.

## Open questions for Marv at the time (from PLAN §5)

Resolved: see PLAN.md §5 and D6 to D9 (bundled weights, English glosses, P1/P3/P4 confirmed, name and bundle id).

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

## WP0b 2026-10-13: the graphs are the contract (D0.9 executed; branch `wp0b-graph-contract`)

Decisions (binding until reversed):

- **D0b.1 Graph input is BGRA uint8 NHWC, any size, all preprocessing in-graph.** The iOS camera
  delivers `kCVPixelFormatType_32BGRA`; the only Dart-side pixel work is the row-padding repack.
- **D0b.2 Detector post-processing is in-graph:** conf threshold is a runtime input; NMS is ONNX
  `NonMaxSuppression`, class-aware through a `[1,2,N]` score tensor in which the non-best class scores 0;
  ≤300 per class (torch: 300 total, irrelevant on a page); output sorted by score with `TopK`. The
  reference's double filter (obj>t, then obj·cls>t) collapses to the single obj·cls>t since cls ≤ 1.
- **D0b.3 Grey is PIL's fixed-point formula** (integer ops in-graph), not `round(0.299R+…)` as C2 put it;
  identical except at exact .5 ties.
- **D0b.4 The 224 resize is ONNX Resize-18 with antialias=1 on uint8; exact PIL emulation is not
  needed.** Against PIL on the 200 private crops: the interior filter weights are identical (probed
  with impulses) but the two implementations round differently (PIL: two fixed-point passes with an
  8-bit intermediate; ORT: its own accumulation), so 13 358 of the 37 531 differing pixels (of 10.0 M)
  are interior ±1/255; the rest sit on the outermost output row/column where ORT folds the clipped taps
  onto the edge pixel while PIL renormalises (up to 12/255 here, 16/255 seen by the reviewer); 6 crops
  bit-exact. Token sequences, baked fp32 encoder + fp32 decoder vs `ocr_ort.py` fp32: **200/200**
  (criterion was ≥195). The encoder is therefore opset 18 (`version_converter` from the opset-17
  export); detector and decoder stay at 17. A matrix formulation of PIL's exact fixed-point resample
  was designed and rejected.
- **D0b.5 The letterbox resize is float bilinear**, cv2 is fixed-point on uint8: the tensors differ by
  ≤0.77/255 on 74 % of pixels. Boxes at conf 0.2 on the 31 private pages: **193/195 reference boxes
  matched at IoU ≥ 0.9, no extra boxes**, max coordinate deviation 9.1 px on 12 MP photos (≈2.7
  letterbox px), max score deviation 0.011. The 2 misses are reference boxes scored 0.206 that the graph
  scores 0.195 and 0.200: threshold edges, not misdetections.
- **D0b.6 CoreML sessions for the detector need `RequireStaticInputShapes=1`.** Without it ORT hands
  the post-NMS `Gather` (dynamic `[M]`) to CoreML and **the run fails on any frame with zero
  detections** ("runtime shape {0} has zero elements"); 9 partitions, 244 ms/page. With it: 7 partitions,
  257 of 296 nodes on CoreML, blank page → `(0,5)`, 106 ms/page warm on the M2 (CPU EP 293 ms), agreement
  with the CPU EP on 28/31 pages; the 3 differences are threshold edges under ANE fp16 (boxes scored
  0.200–0.206 appear or vanish, one 0.354 box suppressed at the IoU edge). Nodes expected on the CPU EP on
  the phone too: the pre-processing (`Slice`/`Transpose`/`Cast` on uint8, `Shape`/`Gather`/`Div`/
  `ReduceMin`/`Round`, `Resize` and `Pad` with dynamic sizes/pads), `ArgMax`/`Equal`/`Where` (one-hot),
  `NonMaxSuppression`, `Gather`/`Squeeze` on `[M]`, the scale `Div`/`Mul`, `Shape`/`TopK`/`Unsqueeze`/
  `Concat`. The 7 partitions are the conv net plus static-shape fragments of the decode; cost is a few
  tensor copies of ≤1.8 MB.
- **D0b.7 `make models` is a legitimate CI source (C8 confirmed):** `quantize_dynamic` run twice gives
  identical sha256, and the decoder built in this worktree is byte-identical to the one WP0 built in the
  parent checkout (sha256 `3f415333…`). The optimum export is byte-reproducible as before.
- **D0b.8 Goldens are the graphs' own outputs on rendered text** (Hiragino Kaku Gothic W6, our own
  sentences): 12 PNG crops + 2 raw `.bgra` crops with row padding (bytesPerRow > width·4, one width
  not a multiple of 4, padding bytes 0x5A) + 4 pages (portrait 1000×1414, landscape 1414×1000 which pads
  the bottom, a 1080×1920 frame-sized page per D0.12, and a page with coloured bubbles). Coverage
  choices: a crop smaller than 224 (upscale path), one exactly 224×224, and a colour trap (text
  `(0,200,97)` on `(255,200,0)`: same grey when R and B are swapped, 65/255 contrast in the right
  order) in one crop and in three bubbles of the colour page; `make_goldens.py` asserts that feeding
  RGBA instead of BGRA changes the ids / the block set, and that every text crop reads back as
  `post_process(rendered)` (the noise crop is exempt and says so: it yields `それは、`, a parity fixture,
  not an accuracy claim). Every golden JSON records the sha256 of the graphs it was made with and
  `check_goldens.py` refuses other graphs, fails on a fixture without its JSON sidecar, and caps the
  JSON tolerance at ±4 px / ±0.05 (the goldens say ±2 px / ±0.02 so other ORT builds and CPUs pass;
  ids are exact). **Why no input-tensor / encoder-output hashes** (PLAN §3 WP0b promised them): the
  preprocessing is inside the graph, so there is no Dart-side tensor to hash any more, and the int8
  encoder output is not bit-stable across EPs / CPUs (dynamic quantisation), so a hash of it would be a
  test of ORT's kernels, not of the port; the token ids and the post-NMS boxes are the stable
  observables. PLAN.md amended accordingly.

Numbers (Apple M2, ORT 1.31, CPU EP unless stated, default threads; Mac latencies are relative, C9):

| | |
|---|---|
| OCR shipped int8 vs fp32 reference (`ocr_ort.py`) | token sequences 197/200, text 197/200 |
| OCR shipped int8 vs int8 + PIL preprocessing | 197/200 (preprocessing costs 3 crops at int8, 0 at fp32) |
| OCR per crop, shipped graphs | encoder 50 ms median (cold 47), decoder 2.3 ms/step, 86 ms/crop median, p90 128 ms |
| Detector per 12 MP page | CPU 293 ms median (cold 247) incl. the in-graph letterbox of a 2089×3498 frame (≈140 ms of it; the net alone was 151 ms in D0.7); CoreML (D0b.6) 106 ms. A 1080p stream frame (D0.12) has 3.5× fewer input pixels |
| Sizes | detector 28.2 MB, encoder 87.0 MB, decoder 29.6 MB, vocab 24 KB: 144.8 MB (C8) |

What will bite WP2:

- `app/assets/models/` must be declared in `pubspec.yaml` assets and exist before `flutter test`/build
  (`make models` first); the gate does not build the models yet.
- `blocks` may be `[0,5]`; coordinates are unclipped floats; the first decoder token is 2 again.
- Threshold edges flip between CPU and ANE (D0b.6): on-device tests against the page golden need the
  ±2 px/±0.02 tolerance *and* a CPU-EP run for exactness; never assert ANE == CPU box for box.
- The ORT build on iOS must have Resize-18 antialias (ORT ≥ 1.14; the pod pinned in WP2 task 0 is 1.31).
- Pre-processing cost scales with input pixels (D0b.5 numbers are on 12 MP photos); feed the detector
  the stream frame, not `takePicture` output.
