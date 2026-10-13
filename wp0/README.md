# WP0 — feasibility spike (Python only)

Proves that comic-text-detector and manga-ocr run under ONNX Runtime with a hand-rolled decode loop,
and measures what quantisation costs. Results and decisions: `../.claude/wp0/NOTES.md`.

```bash
uv venv --python 3.14 .venv && uv pip install --python .venv/bin/python -r requirements.lock.txt
.venv/bin/python make_fixtures.py        # photos in ~/Downloads/frieren_ch01 -> fixtures/private/ (gitignored)
.venv/bin/python export_detector.py      # -> models/detector_fp32.onnx + parity + timing
.venv/bin/optimum-cli export onnx -m kha-white/manga-ocr-base --task image-to-text --opset 17 models/ocr_fp32
.venv/bin/python quantise.py             # -> models/*_int8*, *_fp16*
.venv/bin/python parity_check.py 10      # greedy ORT == torch greedy, token for token
.venv/bin/python bench_ocr.py            # -> results/ocr.json
.venv/bin/python bench_detector.py       # -> results/detector.json
.venv/bin/python time_ocr.py             # uncontended latency
```

`ocr_ort.py` was the WP0 reference; since WP0b the built graphs are the contract (below).
`models/`, `fixtures/private/` and `results/` are gitignored: weights, book photos and OCRed book text.

## WP0b — the graphs are the contract (D0.9)

```bash
make models                              # == .venv/bin/python build_graphs.py  -> ../app/assets/models/ (gitignored)
make models-check                        # == .venv/bin/python check_goldens.py -> graphs vs ../app/test/goldens/
.venv/bin/python make_goldens.py         # re-render the synthetic goldens (needs Hiragino, i.e. macOS)
.venv/bin/python validate_graphs.py      # graphs vs the WP0 reference pipeline on fixtures/private/ (local only)
.venv/bin/python build_graphs.py --check-determinism   # quantise twice, compare sha256
```

`build_graphs.py` re-runs the two fp32 exports (optimum for manga-ocr, torch for the blocks-only
comic-text-detector head; both deterministic, C8) and bakes the preprocessing into the graphs, so Dart
hands them a raw BGRA frame: `detector.onnx` (letterbox + yolov5 head + decode + NonMaxSuppression,
boxes in input pixels), `ocr_encoder.onnx` (PIL-exact grey + antialiased 224 resize + normalise + int8 ViT)
and `ocr_decoder.onnx` (int8, I/O unchanged). `manifest.json` carries sha256, sizes, opsets and the I/O
contract. `app_graphs.py` runs them the way the Dart port will (the greedy loop and detokenisation are
the only logic left outside the graphs). Numbers and decisions D0b.x: `../.claude/wp0/NOTES.md`.
