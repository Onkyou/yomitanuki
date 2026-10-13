"""WP0b: re-run the built graphs (app/assets/models/) against the committed synthetic goldens
(app/test/goldens/) and exit non-zero on any mismatch. `make models-check`.

Every .png / .bgra fixture must have its .json sidecar (a missing sidecar is a failure, not a skip),
and every sidecar's models_sha256 must equal the graphs being checked. OCR goldens: the token id
sequence must match exactly and the detokenised text must equal the recorded text; .bgra fixtures
are raw rows with padding (bytesPerRow > width*4) and are repacked here first. Detector goldens: same
number of blocks, each golden block matched one-to-one by an output block within the JSON's tolerance,
capped at +-4 px / +-0.05 score whatever the JSON says.

Usage: wp0/.venv/bin/python wp0/check_goldens.py [--goldens DIR] [--models DIR]
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_graphs import MODELS, AppGraphs, to_bgra  # noqa: E402

HERE = Path(__file__).resolve().parent
TOLERANCE_CEILING = {"px": 4, "score": 0.05}
FIXTURE_SUFFIXES = (".png", ".bgra")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_bgra_fixture(path: Path, g: dict) -> np.ndarray:
    """Raw padded rows -> tightly packed [1,H,W,4] (what BgraImage.crop() does in Dart)."""
    w, h, bpr = g["width"], g["height"], g["bytesPerRow"]
    raw = np.frombuffer(path.read_bytes(), np.uint8)
    if raw.size != h * bpr:
        raise ValueError(f"{path.name}: {raw.size} bytes, expected height*bytesPerRow = {h * bpr}")
    return np.ascontiguousarray(raw.reshape(h, bpr)[:, : w * 4].reshape(1, h, w, 4))


def check_models_sha(g: dict, model_hashes: dict) -> list[str]:
    want = g.get("models_sha256")
    if not want:
        return ["no models_sha256 in the golden"]
    return [f"models_sha256 mismatch for {name}: golden {h[:12]}…, loaded {model_hashes.get(name, '?')[:12]}…"
            for name, h in want.items() if model_hashes.get(name) != h]


def check_ocr(graphs: AppGraphs, path: Path, g: dict, model_hashes: dict) -> list[str]:
    errors = check_models_sha(g, model_hashes)
    if "bgra" in g:
        bgra = load_bgra_fixture(path.parent / g["bgra"], g)
    else:
        bgra = to_bgra(Image.open(path.parent / g["png"]))
    ids = graphs.ocr_ids(bgra)
    text = graphs.detokenise(ids)
    if ids != g["ids"]:
        errors.append(f"ids differ: got {ids} expected {g['ids']}")
    if text != g["text"]:
        errors.append(f"text differs: got {text!r} expected {g['text']!r}")
    return errors


def check_detector(graphs: AppGraphs, path: Path, g: dict, model_hashes: dict) -> list[str]:
    errors = check_models_sha(g, model_hashes)
    got = [[float(v) for v in b] for b in graphs.detect(to_bgra(Image.open(path.parent / g["png"])), g["conf_threshold"])]
    tol_px = min(g["tolerance"]["px"], TOLERANCE_CEILING["px"])
    tol_score = min(g["tolerance"]["score"], TOLERANCE_CEILING["score"])
    if (tol_px, tol_score) != (g["tolerance"]["px"], g["tolerance"]["score"]):
        print(f"     note: tolerance {g['tolerance']} capped to px={tol_px} score={tol_score}")
    if len(got) != len(g["blocks"]):
        errors.append(f"block count differs: got {len(got)} expected {len(g['blocks'])}")
    unused = list(range(len(got)))
    for want in g["blocks"]:
        hit = next((j for j in unused if all(abs(got[j][k] - want[k]) <= tol_px for k in range(4))
                    and abs(got[j][4] - want[4]) <= tol_score), None)
        if hit is None:
            errors.append(f"no output block within tolerance of {want}")
        else:
            unused.remove(hit)
    for j in unused:
        errors.append(f"unexpected output block {[round(v, 2) for v in got[j]]}")
    return errors


def fixtures_with_sidecars(folder: Path) -> list[tuple[Path, Path | None]]:
    """Every fixture file, paired with its sidecar JSON or None when it is missing."""
    out = []
    for f in sorted(folder.iterdir()) if folder.is_dir() else []:
        if f.suffix in FIXTURE_SUFFIXES:
            side = f.with_suffix(".json")
            out.append((f, side if side.exists() else None))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--goldens", type=Path, default=HERE.parent / "app/test/goldens")
    ap.add_argument("--models", type=Path, default=MODELS)
    args = ap.parse_args()
    graphs = AppGraphs(args.models)
    model_hashes = {n: sha256(args.models / n) for n in ("detector.onnx", "ocr_encoder.onnx", "ocr_decoder.onnx")}
    plan = [(f, side, check_ocr) for f, side in fixtures_with_sidecars(args.goldens / "ocr")]
    plan += [(f, side, check_detector) for f, side in fixtures_with_sidecars(args.goldens / "detector")]
    if not plan:
        print(f"no goldens under {args.goldens}")
        return 1
    failed = 0
    for fixture, side, fn in plan:
        rel = fixture.relative_to(args.goldens)
        if side is None:
            errors = [f"missing sidecar {fixture.with_suffix('.json').name}"]
        else:
            g = json.loads(side.read_text(encoding="utf-8"))
            errors = fn(graphs, side, g, model_hashes)
        if errors:
            failed += 1
            print(f"FAIL {rel}")
            for e in errors:
                print(f"     {e}")
        else:
            print(f"ok   {rel}")
    if failed:
        print(f"{failed} of {len(plan)} goldens FAILED")
        return 1
    print(f"all {len(plan)} goldens match {args.models}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
