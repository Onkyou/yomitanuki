"""WP0 fixture builder: run the reference fp32 torch pipeline on the local photos.

For every photo in SRC (EXIF-rotated, which mokuro 0.2.5 does NOT do), run
comic-text-detector to get text blocks, crop each block with a margin and OCR
the whole crop with manga-ocr (fp32, torch). The crops and the fp32 text are
the WP0 reference set in fixtures/private/ (gitignored, P4).

Usage: python make_fixtures.py [--limit N] [--device cpu|mps]
"""
import argparse, json, sys, time
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageOps

HERE = Path(__file__).parent
SRC = Path.home() / "Downloads/frieren_ch01"
OUT = HERE / "fixtures/private"
MARGIN = 0.08  # fraction of box size added on each side before OCR


def crop_block(img: Image.Image, xyxy, margin=MARGIN):
    x0, y0, x1, y1 = xyxy
    w, h = x1 - x0, y1 - y0
    mx, my = int(w * margin), int(h * margin)
    box = (max(0, x0 - mx), max(0, y0 - my), min(img.width, x1 + mx), min(img.height, y1 + my))
    return img.crop(box), box


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--device", default="cpu")
    args = ap.parse_args()

    from comic_text_detector.inference import TextDetector
    from manga_ocr import MangaOcr
    from mokuro.cache import cache

    det = TextDetector(model_path=cache.comic_text_detector, input_size=1024, device=args.device, act="leaky")
    mocr = MangaOcr(force_cpu=args.device == "cpu")

    (OUT / "crops").mkdir(parents=True, exist_ok=True)
    (OUT / "pages").mkdir(parents=True, exist_ok=True)
    files = sorted(SRC.glob("IMG_*.jpg"))
    if args.limit:
        files = files[: args.limit]
    manifest = []
    for f in files:
        pil = ImageOps.exif_transpose(Image.open(f)).convert("RGB")
        # detector wants BGR uint8 HWC like cv2.imread
        bgr = np.ascontiguousarray(np.array(pil)[:, :, ::-1])
        t0 = time.perf_counter()
        mask, mask_refined, blk_list = det(bgr, refine_mode=1, keep_undetected_mask=True)
        t_det = time.perf_counter() - t0
        page = {"page": f.stem, "width": pil.width, "height": pil.height, "det_s": round(t_det, 3),
                "blocks": [{"box": [int(v) for v in b.xyxy], "vertical": bool(b.vertical),
                            "font_size": float(b.font_size)} for b in blk_list]}
        (OUT / "pages" / f"{f.stem}.json").write_text(json.dumps(page, ensure_ascii=False, indent=1))
        for i, b in enumerate(blk_list):
            crop, box = crop_block(pil, [int(v) for v in b.xyxy])
            name = f"{f.stem}_{i:02d}.png"
            crop.save(OUT / "crops" / name)
            t0 = time.perf_counter()
            text = mocr(crop)
            t_ocr = time.perf_counter() - t0
            manifest.append({"crop": name, "page": f.stem, "box": list(box), "vertical": bool(b.vertical),
                             "text_fp32": text, "ocr_s": round(t_ocr, 3)})
            print(f"{name} v={int(b.vertical)} {t_ocr:.2f}s {text}", flush=True)
        print(f"== {f.stem}: {len(blk_list)} blocks, det {t_det:.2f}s", flush=True)
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    print(f"wrote {len(manifest)} crops")


if __name__ == "__main__":
    main()
