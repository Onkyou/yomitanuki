"""WP0 C6: CER of beam (manga-ocr default), ORT fp32 greedy and ORT int8 greedy against the
human-verified fixtures/private/ground_truth.json. Only entries with verified=true count."""
import json
from pathlib import Path
import jiwer
from PIL import Image
from ocr_ort import OrtMangaOcr

HERE = Path(__file__).parent
PRIV = HERE / "fixtures/private"
gt = [g for g in json.loads((PRIV / "ground_truth.json").read_text()) if g.get("verified")]
if not gt:
    raise SystemExit("no verified entries yet")
beam = {e["crop"]: e["text_fp32"] for e in json.loads((PRIV / "manifest.json").read_text())}
refs = [g["text"] for g in gt]
crops = [Image.open(PRIV / "crops" / g["crop"]).convert("RGB") for g in gt]
rows = [("beam4 (manga-ocr default)", [beam[g["crop"]] for g in gt])]
for d in ["ocr_fp32", "ocr_int8"]:
    ocr = OrtMangaOcr(HERE / "models" / d)
    rows.append((f"{d} greedy", [ocr(im) for im in crops]))
print(f"{len(gt)} verified bubbles")
for name, hyps in rows:
    print(f"{name:28s} CER {jiwer.cer(refs, hyps)*100:5.2f} %   exact {sum(r == h for r, h in zip(refs, hyps))}/{len(refs)}")
