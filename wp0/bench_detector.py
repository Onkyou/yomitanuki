"""WP0 detector benchmark: ORT variants vs torch on all private pages, compared on the final
text blocks (after CTD's own NMS / DBNet post-processing), not on raw tensors.
Match = IoU >= 0.7 between a torch block and an ORT block. Reports precision/recall/latency/size."""
import json, sys, time, statistics as st
from pathlib import Path
import numpy as np, torch, onnxruntime as ort
from PIL import Image, ImageOps
from comic_text_detector.inference import TextDetector
from mokuro.cache import cache

HERE = Path(__file__).parent
pages = sorted((Path.home() / "Downloads/frieren_ch01").glob("IMG_*.jpg"))
limit = int(sys.argv[1]) if len(sys.argv) > 1 else len(pages)
pages = pages[:limit]


class OrtNet:
    """Drop-in for TextDetBase.forward on the torch backend: takes the torch tensor, returns torch tensors."""
    def __init__(self, path, providers):
        self.sess = ort.InferenceSession(str(path), providers=providers)
        self.ms = []
    def __call__(self, x):
        t0 = time.perf_counter()
        blks, mask, lines = self.sess.run(None, {"image": x.numpy()})
        self.ms.append((time.perf_counter() - t0) * 1000)
        return torch.from_numpy(blks), torch.from_numpy(mask), torch.from_numpy(lines)


def iou(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1]); x1, y1 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, x1 - x0) * max(0, y1 - y0)
    return inter / ((a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - inter + 1e-9)


def blocks(det, bgr):
    _, _, blk_list = det(bgr, refine_mode=1, keep_undetected_mask=True)
    return [[int(v) for v in b.xyxy] for b in blk_list]


imgs = [np.ascontiguousarray(np.array(ImageOps.exif_transpose(Image.open(p)).convert("RGB"))[:, :, ::-1]) for p in pages]
det = TextDetector(model_path=cache.comic_text_detector, input_size=1024, device="cpu", act="leaky")
torch_net = det.net
ref, tms = [], []
for im in imgs:
    t0 = time.perf_counter(); ref.append(blocks(det, im)); tms.append((time.perf_counter() - t0) * 1000)
results = {"torch fp32": {"blocks": sum(map(len, ref)), "median_ms_full": round(st.median(tms))}}
print("torch", results["torch fp32"], flush=True)
variants = [("detector_fp32.onnx", ["CPUExecutionProvider"]), ("detector_int8.onnx", ["CPUExecutionProvider"]),
            ("detector_fp16.onnx", ["CPUExecutionProvider"]),
            ("detector_fp32.onnx", ["CoreMLExecutionProvider", "CPUExecutionProvider"]),
            ("detector_fp16.onnx", ["CoreMLExecutionProvider", "CPUExecutionProvider"])]
for fname, prov in variants:
    path = HERE / "models" / fname
    if not path.exists():
        print("skip", fname); continue
    net = OrtNet(path, prov); det.net = net
    name = f"{fname} {'coreml' if 'CoreML' in prov[0] else 'cpu'}"
    tp = fp = fn = 0
    for r, im in zip(ref, imgs):
        got = blocks(det, im)
        matched = set()
        for g in got:
            j = max(range(len(r)), key=lambda k: iou(g, r[k]), default=None)
            if j is not None and iou(g, r[j]) >= 0.7 and j not in matched:
                matched.add(j); tp += 1
            else:
                fp += 1
        fn += len(r) - len(matched)
    net.ms = net.ms[1:] or net.ms
    results[name] = {"precision": round(tp / max(1, tp + fp), 3), "recall": round(tp / max(1, tp + fn), 3),
                     "tp": tp, "fp": fp, "fn": fn, "median_ms_model": round(st.median(net.ms)),
                     "size_mb": round(path.stat().st_size / 1e6, 1), "provider": net.sess.get_providers()[0]}
    print(name, results[name], flush=True)
(HERE / "results").mkdir(exist_ok=True)
(HERE / "results/detector.json").write_text(json.dumps(results, indent=1))
