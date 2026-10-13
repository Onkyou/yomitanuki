"""Sequential, uncontended latency for the two candidate OCR variants (CPU EP, default threads)."""
import json, time, statistics as st
from pathlib import Path
from PIL import Image
from ocr_ort import OrtMangaOcr
HERE = Path(__file__).parent
man = json.loads((HERE / "fixtures/private/manifest.json").read_text())
crops = [Image.open(HERE / "fixtures/private/crops" / e["crop"]).convert("RGB") for e in man]
for d in ["ocr_fp32", "ocr_int8"]:
    ocr = OrtMangaOcr(HERE / "models" / d); ocr(crops[0])
    tot, enc, dec, steps = [], [], [], []
    for img in crops:
        t0 = time.perf_counter(); ocr(img); tot.append(time.perf_counter() - t0)
        enc.append(ocr.last["enc_s"]); dec.append(ocr.last["dec_s"]); steps.append(ocr.last["steps"])
    print(f"{d}: median {st.median(tot)*1000:.0f} ms, p90 {sorted(tot)[180]*1000:.0f} ms, encoder {st.median(enc)*1000:.0f} ms, decoder {sum(dec)/sum(steps)*1000:.1f} ms/step x {st.mean(steps):.1f} steps")
