"""WP0b: re-run the built graphs (app/assets/models/) against the committed synthetic goldens
(app/test/goldens/) and exit non-zero on any mismatch. `make models-check`.

OCR goldens: the token id sequence must match exactly and the detokenised text must equal the
recorded text. Detector goldens: same number of blocks, each golden block matched one-to-one by an
output block within the JSON's tolerance (+-2 px per coordinate, +-0.02 score).

Usage: wp0/.venv/bin/python wp0/check_goldens.py [--goldens DIR] [--models DIR]
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_graphs import MODELS, AppGraphs, to_bgra  # noqa: E402

HERE = Path(__file__).resolve().parent


def check_ocr(graphs: AppGraphs, path: Path) -> list[str]:
    g = json.loads(path.read_text(encoding="utf-8"))
    ids = graphs.ocr_ids(to_bgra(Image.open(path.parent / g["png"])))
    text = graphs.detokenise(ids)
    errors = []
    if ids != g["ids"]:
        errors.append(f"ids differ: got {ids} expected {g['ids']}")
    if text != g["text"]:
        errors.append(f"text differs: got {text!r} expected {g['text']!r}")
    return errors


def check_detector(graphs: AppGraphs, path: Path) -> list[str]:
    g = json.loads(path.read_text(encoding="utf-8"))
    got = [[float(v) for v in b] for b in graphs.detect(to_bgra(Image.open(path.parent / g["png"])), g["conf_threshold"])]
    tol_px, tol_score = g["tolerance"]["px"], g["tolerance"]["score"]
    errors = []
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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--goldens", type=Path, default=HERE.parent / "app/test/goldens")
    ap.add_argument("--models", type=Path, default=MODELS)
    args = ap.parse_args()
    graphs = AppGraphs(args.models)
    checks = [(p, check_ocr) for p in sorted((args.goldens / "ocr").glob("*.json"))]
    checks += [(p, check_detector) for p in sorted((args.goldens / "detector").glob("*.json"))]
    if not checks:
        print(f"no goldens under {args.goldens}")
        return 1
    failed = 0
    for path, fn in checks:
        errors = fn(graphs, path)
        rel = path.relative_to(args.goldens)
        if errors:
            failed += 1
            print(f"FAIL {rel}")
            for e in errors:
                print(f"     {e}")
        else:
            print(f"ok   {rel}")
    if failed:
        print(f"{failed} of {len(checks)} goldens FAILED")
        return 1
    print(f"all {len(checks)} goldens match {args.models}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
