"""WP0b: render synthetic goldens (P4: our own text, a macOS system font, nothing from a book) and
record what the built graphs say about them. These are WP2's first red tests.

  app/test/goldens/ocr/<name>.png + <name>.json   token ids + text from ocr_encoder/ocr_decoder
  app/test/goldens/detector/page_01.png + .json   blocks from detector.onnx at conf 0.2

Deterministic: fixed strings, fixed layout, a fixed RNG seed for the noise crop. The PNGs are the
fixtures; the renderer only exists to regenerate them (needs Hiragino, i.e. a Mac).

Usage: wp0/.venv/bin/python wp0/make_goldens.py [--out app/test/goldens]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_graphs import CONF_DEFAULT, AppGraphs, to_bgra  # noqa: E402

HERE = Path(__file__).resolve().parent
FONTS = ["/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"]
ROTATED = set("ー…―～（）「」")  # glyphs that turn 90° in vertical writing
TOP_RIGHT = set("、。")  # punctuation that sits in the top-right quadrant in vertical writing
SMALL = set("っゃゅょぁぃぅぇぉッャュョァィゥェォ")

# name -> (orientation, text, canvas size, font px). Sizes mimic real crops (2-4x the 224 input).
CROPS = {
    "v_single": ("v", "魔王を倒した勇者", (260, 760), 64),
    "v_two_columns": ("v", "この街には昔から|伝わる話がある", (420, 700), 56),
    "v_katakana": ("v", "カメラを向けて", (240, 620), 60),
    "v_digits_ellipsis": ("v", "３日で終わる…", (240, 620), 60),
    "v_bubble": ("v", "わかった。|行こう", (520, 640), 60),
    "h_single": ("h", "本を読むのが好きです", (880, 200), 64),
    "h_digits_ellipsis": ("h", "10年後...また会おう", (960, 200), 60),
    "h_mixed": ("h", "今日は天気がいいね", (820, 200), 60),
    "blank_noise": ("noise", "", (300, 400), 0),
}
PAGE_BUBBLES = [  # (cx, cy, rx, ry, text columns) on a 1000x1414 page
    (780, 230, 150, 190, "魔王を倒した|勇者がいた"),
    (260, 300, 130, 170, "本当に？"),
    (700, 720, 170, 200, "この街には|昔から伝わる|話がある"),
    (240, 760, 120, 150, "行こう"),
    (520, 1150, 220, 160, "h:10年後...また会おう"),
    (160, 1200, 110, 140, "はい。"),
]


def font(px: int) -> ImageFont.FreeTypeFont:
    for f in FONTS:
        if Path(f).exists():
            return ImageFont.truetype(f, px)
    sys.exit(f"no Hiragino font found, looked at {FONTS}")


def draw_vertical(img: Image.Image, columns: list[str], x_right: int, y_top: int, px: int, fill="black"):
    """Columns right to left, one glyph per cell, with the usual rotations / offsets."""
    fnt = font(px)
    for ci, col in enumerate(columns):
        x = x_right - px - ci * int(px * 1.45)
        for ri, ch in enumerate(col):
            y = y_top + ri * int(px * 1.12)
            if ch in ROTATED:
                tile = Image.new("L", (px * 2, px * 2), 0)
                ImageDraw.Draw(tile).text((px // 2, px // 2), ch, font=fnt, fill=255)
                tile = tile.rotate(-90, resample=Image.BICUBIC)
                img.paste(Image.new("RGB", tile.size, fill), (x - px // 2, y - px // 2), tile)
            elif ch in TOP_RIGHT:
                ImageDraw.Draw(img).text((x + px * 0.55, y - px * 0.55), ch, font=fnt, fill=fill)
            elif ch in SMALL:
                ImageDraw.Draw(img).text((x + px * 0.12, y - px * 0.12), ch, font=fnt, fill=fill)
            else:
                ImageDraw.Draw(img).text((x, y), ch, font=fnt, fill=fill)


def draw_horizontal(img: Image.Image, text: str, x: int, y: int, px: int, fill="black"):
    ImageDraw.Draw(img).text((x, y), text, font=font(px), fill=fill)


def render_crop(kind: str, text: str, size: tuple[int, int], px: int) -> Image.Image:
    w, h = size
    if kind == "noise":
        rng = np.random.default_rng(0)
        arr = np.clip(rng.normal(235, 12, (h, w)), 0, 255).astype(np.uint8)
        return Image.fromarray(arr).convert("RGB")
    img = Image.new("RGB", size, "white")
    cols = text.split("|")
    if kind == "v":
        ncols = len(cols)
        text_w = px + (ncols - 1) * int(px * 1.45)
        x_right = (w + text_w) // 2
        y_top = (h - max(len(c) for c in cols) * int(px * 1.12)) // 2 + px // 8
        draw_vertical(img, cols, x_right, y_top, px)
    else:
        fnt = font(px)
        tw = ImageDraw.Draw(img).textlength(text, font=fnt)
        draw_horizontal(img, text, int((w - tw) // 2), (h - px) // 2 - px // 8, px)
    return img


def render_bubble_crop(text: str, size: tuple[int, int], px: int) -> Image.Image:
    img = Image.new("RGB", size, (235, 235, 235))
    d = ImageDraw.Draw(img)
    w, h = size
    d.ellipse([20, 20, w - 20, h - 40], fill="white", outline="black", width=4)
    d.polygon([(w // 2 - 30, h - 60), (w // 2 + 10, h - 60), (w // 2 - 50, h - 5)], fill="white", outline="black")
    d.line([(w // 2 - 30, h - 60), (w // 2 + 10, h - 60)], fill="white", width=6)
    cols = text.split("|")
    text_w = px + (len(cols) - 1) * int(px * 1.45)
    draw_vertical(img, cols, (w + text_w) // 2, (h - max(len(c) for c in cols) * int(px * 1.12)) // 2, px)
    return img


def render_page() -> Image.Image:
    img = Image.new("RGB", (1000, 1414), "white")
    d = ImageDraw.Draw(img)
    for box in [(40, 40, 960, 520), (40, 560, 960, 980), (40, 1020, 960, 1374)]:  # panel borders
        d.rectangle(box, outline="black", width=5)
    rng = np.random.default_rng(1)  # light screentone dots so the page is not pure white
    for _ in range(2500):
        x, y = int(rng.integers(50, 950)), int(rng.integers(570, 970))
        d.ellipse([x, y, x + 3, y + 3], fill=(200, 200, 200))
    for cx, cy, rx, ry, text in PAGE_BUBBLES:
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill="white", outline="black", width=4)
        if text.startswith("h:"):
            draw_horizontal(img, text[2:], cx - rx + 40, cy - 28, 44)
        else:
            cols = text.split("|")
            px = 44
            text_w = px + (len(cols) - 1) * int(px * 1.45)
            draw_vertical(img, cols, cx + text_w // 2, cy - (max(len(c) for c in cols) * int(px * 1.12)) // 2, px)
    draw_vertical(img, ["ドン"], 160, 80, 110)  # a sound effect outside any bubble
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=HERE.parent / "app/test/goldens")
    args = ap.parse_args()
    graphs = AppGraphs()
    ocr_dir, det_dir = args.out / "ocr", args.out / "detector"
    ocr_dir.mkdir(parents=True, exist_ok=True)
    det_dir.mkdir(parents=True, exist_ok=True)
    for name, (kind, text, size, px) in CROPS.items():
        img = render_bubble_crop(text, size, px) if name == "v_bubble" else render_crop(kind, text, size, px)
        img.save(ocr_dir / f"{name}.png", optimize=True)
        ids = graphs.ocr_ids(to_bgra(img))
        golden = {"png": f"{name}.png", "rendered": text.replace("|", ""), "ids": ids, "text": graphs.detokenise(ids),
                  "note": "ids: exact match required (greedy, start 2, stop 3, max 300); "
                          "text == detokenise(ids) with manga_ocr post_process"}
        (ocr_dir / f"{name}.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{name:20s} rendered={golden['rendered']!r:28s} ocr={golden['text']!r} ({len(ids)} ids)")
    page = render_page()
    page.save(det_dir / "page_01.png", optimize=True)
    blocks = graphs.detect(to_bgra(page), CONF_DEFAULT)
    golden = {"png": "page_01.png", "conf_threshold": CONF_DEFAULT, "width": page.width, "height": page.height,
              "columns": ["x0", "y0", "x1", "y1", "score"],
              "blocks": [[round(float(v), 2) for v in b] for b in blocks],
              "tolerance": {"px": 2, "score": 0.02},
              "note": "same count of blocks; each golden block matched by one output block within +-2 px on every "
                      "coordinate and +-0.02 on the score (order by score descending, ties may swap)"}
    (det_dir / "page_01.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"page_01: {len(blocks)} blocks at conf {CONF_DEFAULT}")
    for b in golden["blocks"]:
        print("   ", b)


if __name__ == "__main__":
    main()
