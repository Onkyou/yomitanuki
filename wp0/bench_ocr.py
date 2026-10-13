"""WP0 OCR benchmark over all private crops.

Reference = manga_ocr's own output (torch fp32, 4-beam, no_repeat_ngram 3) in manifest.json.
Variants: ORT fp32/int8/fp16 x greedy / greedy+no-repeat-3gram, CPU and CoreML EP.
Reports CER (jiwer) vs reference, exact-match rate, latency and model sizes -> results/ocr.json
"""
import json, sys, time, statistics as st
from pathlib import Path
import jiwer
from PIL import Image
from ocr_ort import OrtMangaOcr, preprocess

HERE = Path(__file__).parent
man = json.loads((HERE / "fixtures/private/manifest.json").read_text())
limit = int(sys.argv[1]) if len(sys.argv) > 1 else len(man)
man = man[:limit]
crops = [Image.open(HERE / "fixtures/private/crops" / e["crop"]).convert("RGB") for e in man]
refs = [e["text_fp32"] for e in man]

variants = []
for d in ["ocr_fp32", "ocr_int8", "ocr_fp16"]:
    for ngram in (0, 3):
        variants.append((f"{d} cpu greedy{'' if not ngram else '+nr3'}", d, ["CPUExecutionProvider"], ngram))
variants.append(("ocr_fp32 coreml greedy+nr3", "ocr_fp32", ["CoreMLExecutionProvider", "CPUExecutionProvider"], 3))
variants.append(("ocr_fp16 coreml greedy+nr3", "ocr_fp16", ["CoreMLExecutionProvider", "CPUExecutionProvider"], 3))

results = {}
for name, d, prov, ngram in variants:
    mdir = HERE / "models" / d
    if not (mdir / "decoder_model.onnx").exists():
        print("skip", name); continue
    ocr = OrtMangaOcr(mdir, providers=prov)
    ocr(crops[0], ngram)  # warm-up
    hyps, enc_t, dec_t, steps, tot = [], [], [], [], []
    for img in crops:
        t0 = time.perf_counter()
        hyps.append(ocr(img, ngram))
        tot.append(time.perf_counter() - t0)
        enc_t.append(ocr.last["enc_s"]); dec_t.append(ocr.last["dec_s"]); steps.append(ocr.last["steps"])
    # CER needs non-empty references; drop pairs where the reference is empty
    pairs = [(r, h) for r, h in zip(refs, hyps) if r]
    cer = jiwer.cer([r for r, _ in pairs], [h for _, h in pairs])
    exact = sum(r == h for r, h in zip(refs, hyps)) / len(refs)
    size = sum(p.stat().st_size for p in mdir.glob("*.onnx")) / 1e6
    r = {"cer": round(cer, 4), "exact": round(exact, 3), "n": len(refs), "size_mb": round(size, 1),
         "median_ms": round(st.median(tot) * 1000), "p90_ms": round(sorted(tot)[int(len(tot) * .9)] * 1000),
         "enc_median_ms": round(st.median(enc_t) * 1000), "dec_step_ms": round(sum(dec_t) / sum(steps) * 1000, 1),
         "mean_steps": round(st.mean(steps), 1), "providers": ocr.dec.get_providers()[0]}
    results[name] = r
    print(name, r, flush=True)
    diffs = [(e["crop"], rf, h) for e, rf, h in zip(man, refs, hyps) if rf != h]
    results[name]["diffs"] = diffs
(HERE / "results").mkdir(exist_ok=True)
(HERE / "results/ocr.json").write_text(json.dumps(results, ensure_ascii=False, indent=1))
