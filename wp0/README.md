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

`ocr_ort.py` is the reference the Dart `OcrEngine` adapter (WP2) must match.
`models/`, `fixtures/private/` and `results/` are gitignored: weights, book photos and OCRed book text.
