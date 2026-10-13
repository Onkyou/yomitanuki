"""WP0b: render synthetic goldens (P4: our own text, a macOS system font, nothing from a book) and
record what the built graphs say about them. These are WP2's first red tests.

  app/test/goldens/ocr/<name>.png  + <name>.json   token ids + text from ocr_encoder/ocr_decoder
  app/test/goldens/ocr/<name>.bgra + <name>.json   raw BGRA rows WITH row padding (bytesPerRow >
                                                   width*4) for the Dart repack path; same fields
  app/test/goldens/detector/<page>.png + .json     blocks from detector.onnx at conf 0.2

Coverage on purpose: vertical/horizontal text, digits, an ellipsis, a drawn bubble, noise, a crop
smaller than 224 (upscale path), one exactly 224x224, coloured text on a tinted background and a
page with coloured bubbles (a channel-order mistake must change the result: asserted below), a
portrait page, a landscape page (pads bottom), a 1080x1920 frame-sized page (D0.12).

Every golden JSON carries the sha256 of the graphs it was recorded with; check_goldens.py refuses
to compare against other graphs. Text crops assert text == post_process(rendered), so a broken
regeneration cannot be committed silently (the noise crop is exempt and says so).

Deterministic: fixed strings, fixed layout, fixed RNG seeds. The PNG/.bgra files are the fixtures;
the renderer only regenerates them (needs Hiragino, i.e. a Mac).

Usage: wp0/.venv/bin/python wp0/make_goldens.py [--out app/test/goldens]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_graphs import CONF_DEFAULT, MODELS, AppGraphs, to_bgra  # noqa: E402
from ocr_ort import post_process  # noqa: E402

HERE = Path(__file__).resolve().parent
FONTS = ["/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"]
ROTATED = set("ー…―～（）「」")  # glyphs that turn 90° in vertical writing
TOP_RIGHT = set("、。")  # punctuation that sits in the top-right quadrant in vertical writing
SMALL = set("っゃゅょぁぃぅぇぉッャュョァィゥェォ")
TOLERANCE = {"px": 2, "score": 0.02}
PAD_BYTE = 0x5A  # row padding content in the .bgra fixtures: a repack bug reads these
# The colour trap: text and background have the same grey when R and B are swapped
# (0.114*255 == 0.299*97, same G), and a 65/255 contrast in the correct BGRA order.
TRAP_BG = (255, 200, 0)
TRAP_TEXT = (0, 200, 97)

# name -> (kind, text, canvas size, font px[, colours]). Sizes mimic real crops (2-4x the 224 input).
CROPS = {
    "v_single": ("v", "魔王を倒した勇者", (260, 760), 64),
    "v_two_columns": ("v", "この街には昔から|伝わる話がある", (420, 700), 56),
    "v_katakana": ("v", "カメラを向けて", (240, 620), 60),
    "v_digits_ellipsis": ("v", "３日で終わる…", (240, 620), 60),
    "v_bubble": ("bubble", "わかった。|行こう", (520, 640), 60),
    "h_single": ("h", "本を読むのが好きです", (880, 200), 64),
    "h_digits_ellipsis": ("h", "10年後...また会おう", (960, 200), 60),
    "h_mixed": ("h", "今日は天気がいいね", (820, 200), 60),
    "blank_noise": ("noise", "", (300, 400), 0),
    "v_colour_trap": ("v", "赤と青を間違えるな", (260, 760), 60, (TRAP_BG, TRAP_TEXT)),
    "v_small_upscale": ("v", "小さい", (100, 180), 40),
    "h_exact_224": ("h", "同じ", (224, 224), 80),
}
# raw BGRA fixtures with row padding: name -> (kind, text, size, px, bytesPerRow); one width not a multiple of 4
BGRA_CROPS = {
    "bgra_padded_237": ("h", "行の詰め物", (237, 110), 36, 960),
    "bgra_padded_320": ("v", "余白", (320, 180), 56, 1344),
}
# pages: name -> (size, panels, bubbles (cx, cy, rx, ry, text; "h:" = horizontal; "trap:" = colour trap), sfx)
PAGES = {
    "page_01": ((1000, 1414), [(40, 40, 960, 520), (40, 560, 960, 980), (40, 1020, 960, 1374)],
                [(780, 230, 150, 190, "魔王を倒した|勇者がいた"), (260, 300, 130, 170, "本当に？"),
                 (700, 720, 170, 200, "この街には|昔から伝わる|話がある"), (240, 760, 120, 150, "行こう"),
                 (520, 1150, 220, 160, "h:10年後...また会おう"), (160, 1200, 110, 140, "はい。")],
                (160, 80, 110), 44, (50, 950, 570, 970)),
    "page_02_landscape": ((1414, 1000), [(40, 40, 700, 960), (740, 40, 1374, 480), (740, 520, 1374, 960)],
                          [(540, 250, 150, 190, "魔王を倒した|勇者がいた"), (220, 300, 130, 170, "本当に？"),
                           (420, 720, 170, 200, "この街には|昔から伝わる|話がある"), (1050, 260, 140, 150, "行こう"),
                           (1050, 740, 240, 150, "h:10年後...また会おう"), (1280, 280, 70, 140, "はい。")],
                          (140, 560, 100), 44, (760, 1360, 540, 940)),
    "page_03_frame_1080x1920": ((1080, 1920), [(40, 40, 1040, 700), (40, 740, 1040, 1300), (40, 1340, 1040, 1880)],
                                [(820, 320, 170, 220, "魔王を倒した|勇者がいた"), (300, 400, 150, 190, "本当に？"),
                                 (760, 1000, 190, 230, "この街には|昔から伝わる|話がある"), (280, 1040, 140, 170, "行こう"),
                                 (560, 1600, 250, 180, "h:10年後...また会おう"), (180, 1650, 120, 160, "はい。")],
                                (180, 90, 120), 48, (60, 1020, 760, 1280)),
    "page_04_colour": ((1000, 1414), [(40, 40, 960, 520), (40, 560, 960, 980), (40, 1020, 960, 1374)],
                       [(780, 230, 150, 190, "trap:魔王を倒した|勇者がいた"), (260, 300, 130, 170, "本当に？"),
                        (700, 720, 170, 200, "trap:この街には|昔から伝わる|話がある"), (240, 760, 120, 150, "行こう"),
                        (520, 1150, 220, 160, "trap:h:10年後...また会おう"), (160, 1200, 110, 140, "はい。")],
                       (160, 80, 110), 44, (50, 950, 570, 970)),
}


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


def draw_vertical_centred(img: Image.Image, cols: list[str], cx: int, cy: int, px: int, fill="black"):
    text_w = px + (len(cols) - 1) * int(px * 1.45)
    draw_vertical(img, cols, cx + text_w // 2, cy - (max(len(c) for c in cols) * int(px * 1.12)) // 2, px, fill)


def render_crop(kind: str, text: str, size: tuple[int, int], px: int, colours=None) -> Image.Image:
    w, h = size
    bg, fill = colours if colours else ("white", "black")
    if kind == "noise":
        rng = np.random.default_rng(0)
        return Image.fromarray(np.clip(rng.normal(235, 12, (h, w)), 0, 255).astype(np.uint8)).convert("RGB")
    img = Image.new("RGB", size, bg)
    cols = text.split("|")
    if kind == "bubble":
        img = Image.new("RGB", size, (235, 235, 235))
        d = ImageDraw.Draw(img)
        d.ellipse([20, 20, w - 20, h - 40], fill="white", outline="black", width=4)
        d.polygon([(w // 2 - 30, h - 60), (w // 2 + 10, h - 60), (w // 2 - 50, h - 5)], fill="white", outline="black")
        d.line([(w // 2 - 30, h - 60), (w // 2 + 10, h - 60)], fill="white", width=6)
        draw_vertical_centred(img, cols, w // 2, h // 2 - 10, px)
    elif kind == "v":
        draw_vertical_centred(img, cols, w // 2, h // 2 + px // 8, px, fill)
    else:
        tw = ImageDraw.Draw(img).textlength(text, font=font(px))
        draw_horizontal(img, text, int((w - tw) // 2), (h - px) // 2 - px // 8, px, fill)
    return img


def render_page(size, panels, bubbles, sfx, px, dots) -> Image.Image:
    img = Image.new("RGB", size, "white")
    d = ImageDraw.Draw(img)
    for box in panels:
        d.rectangle(box, outline="black", width=5)
    rng = np.random.default_rng(1)  # light screentone dots in one panel so the page is not pure white
    for _ in range(2500):
        x, y = int(rng.integers(dots[0], dots[1])), int(rng.integers(dots[2], dots[3]))
        d.ellipse([x, y, x + 3, y + 3], fill=(200, 200, 200))
    for cx, cy, rx, ry, text in bubbles:
        trap = text.startswith("trap:")
        text = text.removeprefix("trap:")
        bg, fill = (TRAP_BG, TRAP_TEXT) if trap else ("white", "black")
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=bg, outline="black", width=4)
        if text.startswith("h:"):
            draw_horizontal(img, text[2:], cx - rx + 40, cy - px * 2 // 3, px, fill)
        else:
            draw_vertical_centred(img, text.split("|"), cx, cy, px, fill)
    draw_vertical(img, ["ドン"], sfx[0], sfx[1], sfx[2])  # a sound effect outside any bubble
    return img


def swap_rb(bgra: np.ndarray) -> np.ndarray:
    """The channel-order mistake the colour goldens must catch: RGBA fed where BGRA is expected."""
    return np.ascontiguousarray(bgra[..., [2, 1, 0, 3]])


def blocks_within(got, want, tol) -> bool:
    """Same matching rule as check_goldens.py."""
    if len(got) != len(want):
        return False
    unused = list(range(len(got)))
    for w in want:
        hit = next((j for j in unused if all(abs(got[j][k] - w[k]) <= tol["px"] for k in range(4))
                    and abs(got[j][4] - w[4]) <= tol["score"]), None)
        if hit is None:
            return False
        unused.remove(hit)
    return True


def write_padded_bgra(path: Path, bgra: np.ndarray, bytes_per_row: int):
    _, h, w, _ = bgra.shape
    assert bytes_per_row > w * 4, (bytes_per_row, w)
    rows = np.full((h, bytes_per_row), PAD_BYTE, np.uint8)
    rows[:, : w * 4] = bgra[0].reshape(h, w * 4)
    path.write_bytes(rows.tobytes())


def ocr_golden(graphs: AppGraphs, bgra: np.ndarray, rendered: str, sha: dict, exempt: str | None = None) -> dict:
    ids = graphs.ocr_ids(bgra)
    text = graphs.detokenise(ids)
    if exempt is None:
        expected = post_process(rendered)
        assert text == expected, f"regeneration broken: graphs read {text!r}, rendered {rendered!r} -> expected {expected!r}"
    return {"rendered": rendered, "ids": ids, "text": text,
            "note": ("ids: exact match required (greedy, start 2, stop 3, max 300); text == detokenise(ids) with "
                     "manga_ocr post_process" + ("" if exempt is None else f"; {exempt}")),
            "models_sha256": {k: sha[k] for k in ("ocr_encoder.onnx", "ocr_decoder.onnx")}}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=HERE.parent / "app/test/goldens")
    args = ap.parse_args()
    graphs = AppGraphs()
    manifest = json.loads((MODELS / "manifest.json").read_text(encoding="utf-8"))
    sha = {name: info["sha256"] for name, info in manifest["files"].items()}
    ocr_dir, det_dir = args.out / "ocr", args.out / "detector"
    ocr_dir.mkdir(parents=True, exist_ok=True)
    det_dir.mkdir(parents=True, exist_ok=True)

    for name, spec in CROPS.items():
        kind, text, size, px = spec[:4]
        img = render_crop(kind, text, size, px, spec[4] if len(spec) > 4 else None)
        img.save(ocr_dir / f"{name}.png", optimize=True)
        bgra = to_bgra(img)
        exempt = "noise crop: no rendered text, the recorded output is a parity fixture, not an accuracy claim" \
            if kind == "noise" else None
        golden = {"png": f"{name}.png", **ocr_golden(graphs, bgra, text.replace("|", ""), sha, exempt)}
        if name == "v_colour_trap":
            swapped = graphs.ocr_ids(swap_rb(bgra))
            assert swapped != golden["ids"], "colour trap failed: RGBA-fed ids equal BGRA-fed ids"
            golden["note"] += "; coloured: feeding RGBA instead of BGRA gives different ids (asserted at generation)"
        (ocr_dir / f"{name}.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{name:20s} {size[0]}x{size[1]:<5d} rendered={golden['rendered']!r:28s} ocr={golden['text']!r} ({len(golden['ids'])} ids)")

    for name, (kind, text, size, px, bpr) in BGRA_CROPS.items():
        bgra = to_bgra(render_crop(kind, text, size, px))
        write_padded_bgra(ocr_dir / f"{name}.bgra", bgra, bpr)
        golden = {"bgra": f"{name}.bgra", "width": size[0], "height": size[1], "bytesPerRow": bpr,
                  **ocr_golden(graphs, bgra, text, sha)}
        golden["note"] += (f"; raw 8-bit BGRA rows, bytesPerRow {bpr} > width*4 = {size[0] * 4}, padding bytes are "
                           f"0x{PAD_BYTE:02X}: repack to width*4 before feeding the graph")
        (ocr_dir / f"{name}.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{name:20s} {size[0]}x{size[1]:<5d} bytesPerRow={bpr} ocr={golden['text']!r} ({len(golden['ids'])} ids)")

    for name, (size, panels, bubbles, sfx, px, dots) in PAGES.items():
        page = render_page(size, panels, bubbles, sfx, px, dots)
        page.save(det_dir / f"{name}.png", optimize=True)
        bgra = to_bgra(page)
        blocks = [[round(float(v), 2) for v in b] for b in graphs.detect(bgra, CONF_DEFAULT)]
        golden = {"png": f"{name}.png", "conf_threshold": CONF_DEFAULT, "width": page.width, "height": page.height,
                  "columns": ["x0", "y0", "x1", "y1", "score"], "blocks": blocks, "tolerance": dict(TOLERANCE),
                  "note": "same count of blocks; each golden block matched by one output block within +-2 px on every "
                          "coordinate and +-0.02 on the score (order by score descending, ties may swap)",
                  "models_sha256": {"detector.onnx": sha["detector.onnx"]}}
        if name == "page_04_colour":
            swapped = [[float(v) for v in b] for b in graphs.detect(swap_rb(bgra), CONF_DEFAULT)]
            assert not blocks_within(swapped, blocks, TOLERANCE), "colour trap failed: RGBA-fed blocks match BGRA-fed"
            golden["note"] += (f"; coloured bubbles: feeding RGBA instead of BGRA gives {len(swapped)} blocks instead of "
                               f"{len(blocks)} (asserted at generation)")
        (det_dir / f"{name}.json").write_text(json.dumps(golden, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"{name}: {page.width}x{page.height}, {len(blocks)} blocks at conf {CONF_DEFAULT}")
        for b in blocks:
            print("   ", b)


if __name__ == "__main__":
    main()
