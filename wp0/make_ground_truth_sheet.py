"""WP0 C6: prepare a ground-truth set for a human to verify.

Picks 50 crops (every page represented, horizontal blocks and blocks with digits preferred),
prefills fixtures/private/ground_truth.json with the beam-search text so the human only
corrects, and renders numbered contact sheets (fixtures/private/ground_truth_sheet_N.png)
showing each crop next to its prefilled text.
"""
import json, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
PRIV = HERE / "fixtures/private"
man = json.loads((PRIV / "manifest.json").read_text())
random.seed(7)
by_page = {}
for e in man:
    by_page.setdefault(e["page"], []).append(e)
chosen = []
# one per page first, preferring horizontal / digit-bearing blocks
for page, es in sorted(by_page.items()):
    es = sorted(es, key=lambda e: (e["vertical"], not any(c.isdigit() for c in e["text_fp32"]), random.random()))
    chosen.append(es[0])
rest = [e for e in man if e not in chosen and len(e["text_fp32"]) >= 3]
random.shuffle(rest)
chosen += rest[: 50 - len(chosen)]
chosen.sort(key=lambda e: e["crop"])

gt_path = PRIV / "ground_truth.json"
if gt_path.exists():
    raise SystemExit(f"{gt_path} exists; not overwriting a human's work")
gt = [{"n": i + 1, "crop": e["crop"], "text": e["text_fp32"], "verified": False} for i, e in enumerate(chosen)]
gt_path.write_text(json.dumps(gt, ensure_ascii=False, indent=1))

font = ImageFont.truetype("/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc", 26)
per_sheet, cell_h, w = 10, 230, 1400
for s in range(0, len(gt), per_sheet):
    rows = gt[s : s + per_sheet]
    sheet = Image.new("RGB", (w, cell_h * len(rows)), "white")
    d = ImageDraw.Draw(sheet)
    for i, r in enumerate(rows):
        y = i * cell_h
        im = Image.open(PRIV / "crops" / r["crop"]).convert("RGB")
        im.thumbnail((400, cell_h - 10))
        sheet.paste(im, (60, y + 5))
        d.text((8, y + 8), str(r["n"]), fill="red", font=font)
        d.text((480, y + 20), r["text"], fill="black", font=font)
        d.text((480, y + 70), r["crop"], fill="gray", font=font)
        d.line([(0, y + cell_h - 1), (w, y + cell_h - 1)], fill="lightgray")
    sheet.save(PRIV / f"ground_truth_sheet_{s // per_sheet + 1}.png")
print(f"{len(gt)} crops → {gt_path} and {-(-len(gt) // per_sheet)} sheets")
