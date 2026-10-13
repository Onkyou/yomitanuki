"""WP0b: validate the built graphs (app/assets/models/) against the WP0 reference pipeline on the
private crops and pages (local only, P4). Only aggregate numbers are printed or written.

OCR, token sequences on the private crops:
  A  baked fp32 encoder + fp32 decoder  vs  wp0/ocr_ort.py on the fp32 export (PIL preprocessing)
     -> isolates the in-graph preprocessing; the WP0b exit criterion is >= 195/200
  B  shipped int8 graphs  vs  int8 plain export + PIL preprocessing (isolates preprocessing at int8)
  C  shipped int8 graphs  vs  the fp32 reference (what the app does vs WP0's fp32 numbers)
  plus the pixel-level diff of the baked 224x224 tensor against ocr_ort.preprocess().
Detector, blocks at conf 0.2 on the private pages:
  baked graph vs live_detector.py's path (cv2 letterbox + blocks-only fp32 + postprocess_yolo), IoU >= 0.9,
  plus the pixel-level diff of the baked letterbox tensor against preprocess_img().
Timings: CPU, one cold run and the median of warm runs per graph; CoreML EP partition of the detector.

Usage: wp0/.venv/bin/python wp0/validate_graphs.py [--fixtures DIR] [--photos DIR] [--n 200]
"""
import argparse
import json
import os
import re
import shutil
import statistics as st
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_graphs import MODELS, AppGraphs, to_bgra  # noqa: E402
from ocr_ort import OrtMangaOcr, preprocess  # noqa: E402

HERE = Path(__file__).resolve().parent
WP0_MODELS = HERE / "models"
CONF = 0.2
CPU = ["CPUExecutionProvider"]


def session_with_extra_output(path: Path, tensor: str) -> ort.InferenceSession:
    """A session on `path` that also returns the intermediate `tensor` (to compare preprocessing)."""
    m = onnx.load(str(path))
    m.graph.output.append(onnx.helper.make_tensor_value_info(tensor, onnx.TensorProto.FLOAT, None))
    return ort.InferenceSession(m.SerializeToString(), providers=CPU)


def iou(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, x1 - x0) * max(0, y1 - y0)
    return inter / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter + 1e-9)


def int8_plain_encoder() -> Path:
    """WP0's int8 encoder without baked preprocessing (for comparison B); built once, gitignored."""
    out = WP0_MODELS / "ocr_int8_plain"
    if not (out / "encoder_model.onnx").exists():
        from onnxruntime.quantization import QuantType, quantize_dynamic
        out.mkdir(exist_ok=True)
        quantize_dynamic(str(WP0_MODELS / "ocr_fp32/encoder_model.onnx"), str(out / "encoder_model.onnx"),
                         weight_type=QuantType.QInt8)
        for name in ("decoder_model.onnx", "vocab.txt"):
            (out / name).symlink_to(MODELS / {"decoder_model.onnx": "ocr_decoder.onnx", "vocab.txt": "vocab.txt"}[name])
    return out


def validate_ocr(fixtures: Path, n: int, results: dict):
    man = json.loads((fixtures / "manifest.json").read_text())[:n]
    ref32 = OrtMangaOcr(WP0_MODELS / "ocr_fp32")
    ref8 = OrtMangaOcr(int8_plain_encoder())
    shipped = AppGraphs()
    baked32 = AppGraphs()  # same decode loop, fp32 baked encoder + fp32 decoder
    baked32.enc = session_with_extra_output(WP0_MODELS / "ocr_encoder_fp32_baked.onnx", "ocr_pixel_values")
    baked32.dec = ref32.dec
    counts = {"A_baked32_vs_ref32": 0, "B_shipped8_vs_ref8": 0, "C_shipped8_vs_ref32": 0,
              "A_text": 0, "B_text": 0, "C_text": 0}
    px = {"crops_exact": 0, "max_abs": 0.0, "pixels_differing": 0, "pixels_total": 0}
    t_enc, t_dec_step, t_total = [], [], []
    cold = None
    for e in man:
        img = Image.open(fixtures / "crops" / e["crop"]).convert("RGB")
        bgra = to_bgra(img)
        ids32 = ref32.generate_ids(preprocess(img))
        ids8 = ref8.generate_ids(preprocess(img))
        hidden, tensor = baked32.enc.run(None, {"image": bgra})
        ids_b32 = baked32.greedy_ids(hidden)
        t0 = time.perf_counter()
        h8 = shipped.encode(bgra)
        t1 = time.perf_counter()
        ids_s8 = shipped.greedy_ids(h8)
        t2 = time.perf_counter()
        if cold is None:
            cold = {"encoder_ms": (t1 - t0) * 1000, "decoder_ms": (t2 - t1) * 1000, "steps": len(ids_s8) - 1}
        else:
            t_enc.append((t1 - t0) * 1000)
            t_dec_step.append((t2 - t1) * 1000 / (len(ids_s8) - 1))
            t_total.append((t2 - t0) * 1000)
        counts["A_baked32_vs_ref32"] += ids_b32 == ids32
        counts["B_shipped8_vs_ref8"] += ids_s8 == ids8
        counts["C_shipped8_vs_ref32"] += ids_s8 == ids32
        counts["A_text"] += shipped.detokenise(ids_b32) == ref32.detokenise(ids32)
        counts["B_text"] += shipped.detokenise(ids_s8) == ref8.detokenise(ids8)
        counts["C_text"] += shipped.detokenise(ids_s8) == ref32.detokenise(ids32)
        d = np.abs(tensor - preprocess(img)) * 127.5  # back to 0..255 units
        px["crops_exact"] += int(d.max() == 0)
        px["max_abs"] = max(px["max_abs"], float(d.max()))
        px["pixels_differing"] += int((d[0, 0] > 0).sum())
        px["pixels_total"] += d[0, 0].size
    results["ocr"] = {"crops": len(man), "token_sequences_equal": counts, "preprocess_pixels": px,
                      "timing_cpu_ms": {"cold_first_crop": cold,
                                        "warm_median": {"encoder": st.median(t_enc), "decoder_per_step": st.median(t_dec_step),
                                                        "ocr_per_crop": st.median(t_total)},
                                        "warm_p90_ocr_per_crop": sorted(t_total)[int(0.9 * len(t_total))]}}
    print(json.dumps(results["ocr"], indent=1))


def validate_detector(fixtures: Path, photos: Path, results: dict):
    import torch
    from comic_text_detector.inference import postprocess_yolo, preprocess_img

    pages = sorted((fixtures / "pages").glob("*.json"))
    ref_net = ort.InferenceSession(str(WP0_MODELS / "detector_blocks_1024_fp32.onnx"), providers=CPU)
    baked = session_with_extra_output(MODELS / "detector.onnx", "det_pre_tensor")
    conf = np.array([CONF], np.float32)
    stats = {"pages": 0, "ref_boxes": 0, "matched_iou_0.9": 0, "matched_iou_0.5": 0, "baked_boxes": 0,
             "max_px_dev_matched": 0.0, "max_score_dev_matched": 0.0}
    px = {"pages_exact": 0, "max_abs": 0.0, "pixels_differing": 0, "pixels_total": 0}
    times, cold = [], None
    for pj in pages:
        ref = json.loads(pj.read_text())
        pil = ImageOps.exif_transpose(Image.open(photos / f"{ref['page']}.jpg")).convert("RGB")
        bgr = np.ascontiguousarray(np.array(pil)[:, :, ::-1])
        x, _, dw, dh = preprocess_img(bgr, input_size=(1024, 1024), to_tensor=True)
        blks = ref_net.run(None, {"image": x.numpy()})[0]
        rr = (pil.width / (1024 - dw), pil.height / (1024 - dh))
        det = postprocess_yolo(torch.from_numpy(blks)[None], CONF, 0.35, rr)
        ref_boxes = [[float(v) for v in b] + [float(c)] for b, c in zip(det[0], det[2])]
        t0 = time.perf_counter()
        got, tensor = baked.run(None, {"image": to_bgra(pil), "conf_threshold": conf})
        dt = (time.perf_counter() - t0) * 1000
        if cold is None:
            cold = dt
        else:
            times.append(dt)
        d = np.abs(tensor - x.numpy()) * 255
        px["pages_exact"] += int(d.max() == 0)
        px["max_abs"] = max(px["max_abs"], float(d.max()))
        px["pixels_differing"] += int((d[0, 0] > 0).sum())
        px["pixels_total"] += d[0, 0].size
        stats["pages"] += 1
        stats["ref_boxes"] += len(ref_boxes)
        stats["baked_boxes"] += len(got)
        used = set()
        for r in ref_boxes:
            best, bj = 0.0, None
            for j, g in enumerate(got):
                if j in used:
                    continue
                v = iou(r, g)
                if v > best:
                    best, bj = v, j
            if bj is not None and best >= 0.5:
                stats["matched_iou_0.5"] += 1
            if bj is not None and best >= 0.9:
                used.add(bj)
                stats["matched_iou_0.9"] += 1
                stats["max_px_dev_matched"] = max(stats["max_px_dev_matched"], float(np.abs(np.array(r[:4]) - got[bj][:4]).max()))
                stats["max_score_dev_matched"] = max(stats["max_score_dev_matched"], abs(r[4] - float(got[bj][4])))
    results["detector"] = {"conf": CONF, "boxes": stats, "letterbox_pixels": px,
                           "timing_cpu_ms": {"cold_first_page": cold, "warm_median": st.median(times), "warm_max": max(times)}}
    print(json.dumps(results["detector"], indent=1))


def coreml_partition(results: dict, photos: Path, fixtures: Path):
    """Which nodes of detector.onnx the CoreML EP takes on this Mac with the D0.10 + D0b.6 options,
    that a frame with zero detections still runs, and the latency."""
    if "CoreMLExecutionProvider" not in ort.get_available_providers():
        results["coreml"] = "CoreML EP not available"
        return
    cache = Path(tempfile.mkdtemp(prefix="coreml-cache-"))
    so = ort.SessionOptions()
    so.log_severity_level = 1
    log = tempfile.NamedTemporaryFile(delete=False, suffix=".log")
    saved = os.dup(2)
    os.dup2(log.fileno(), 2)
    try:
        sess = ort.InferenceSession(str(MODELS / "detector.onnx"), so, providers=[
            ("CoreMLExecutionProvider", {"ModelFormat": "NeuralNetwork", "MLComputeUnits": "CPUAndNeuralEngine",
                                         "RequireStaticInputShapes": "1",  # D0b.6: dynamic [M] post-NMS nodes stay on CPU
                                         "ModelCacheDirectory": str(cache)}), "CPUExecutionProvider"])
    finally:
        os.dup2(saved, 2)
    text = Path(log.name).read_text(errors="replace")
    m = re.search(r"number of partitions supported by CoreML: (\d+) number of nodes in the graph: (\d+) number of nodes supported by CoreML: (\d+)", text)
    info = {"partitions": int(m.group(1)) if m else None, "nodes": int(m.group(2)) if m else None,
            "nodes_on_coreml": int(m.group(3)) if m else None}
    blank = {"image": np.full((1, 1200, 900, 4), 255, np.uint8), "conf_threshold": np.array([CONF], np.float32)}
    info["blank_page_blocks_shape"] = list(sess.run(None, blank)[0].shape)  # raises without RequireStaticInputShapes
    pages = sorted((fixtures / "pages").glob("*.json"))
    cpu = ort.InferenceSession(str(MODELS / "detector.onnx"), providers=CPU)
    times, agree = [], 0
    for pj in pages:
        ref = json.loads(pj.read_text())
        pil = ImageOps.exif_transpose(Image.open(photos / f"{ref['page']}.jpg")).convert("RGB")
        feed = {"image": to_bgra(pil), "conf_threshold": np.array([CONF], np.float32)}
        t0 = time.perf_counter()
        a = sess.run(None, feed)[0]
        times.append((time.perf_counter() - t0) * 1000)
        b = cpu.run(None, feed)[0]
        agree += len(a) == len(b) and all(any(iou(x, y) >= 0.9 for y in b) for x in a)
    info["latency_ms_cold"] = times[0]
    info["latency_ms_warm_median"] = st.median(times[1:])
    info["pages_agree_with_cpu"] = f"{agree}/{len(pages)}"
    results["coreml"] = info
    print(json.dumps(info, indent=1))
    os.unlink(log.name)
    shutil.rmtree(cache, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fixtures", type=Path, default=HERE / "fixtures/private")
    ap.add_argument("--photos", type=Path, default=Path.home() / "Downloads/frieren_ch01")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--skip", nargs="*", default=[], choices=["ocr", "detector", "coreml"])
    args = ap.parse_args()
    results = {}
    if "ocr" not in args.skip:
        validate_ocr(args.fixtures, args.n, results)
    if "detector" not in args.skip:
        validate_detector(args.fixtures, args.photos, results)
    if "coreml" not in args.skip:
        coreml_partition(results, args.photos, args.fixtures)
    out = HERE / "results/wp0b_validation.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(results, indent=1))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
