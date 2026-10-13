"""WP0 addendum (D10): can bubble boxes come from a camera stream?

Exports a BLOCKS-ONLY detector (yolov5 head, no UNet mask / DBNet lines) at 1024 and 640 input and
measures latency (CPU and CoreML EP) plus block recall against the full-pipeline reference blocks
in fixtures/private/pages/*.json (IoU >= 0.5, the looser threshold a tap target needs)."""
import json, time, statistics as st
from pathlib import Path
import numpy as np, torch, onnxruntime as ort
from PIL import Image, ImageOps
from comic_text_detector.basemodel import TextDetBase
from comic_text_detector.inference import preprocess_img, postprocess_yolo
from mokuro.cache import cache
from onnxruntime.transformers.float16 import convert_float_to_float16
import onnx

HERE = Path(__file__).parent
pages = sorted((HERE / "fixtures/private/pages").glob("*.json"))


class BlocksOnly(torch.nn.Module):
    def __init__(self, net):
        super().__init__(); self.blk_det = net.blk_det
    def forward(self, x):
        blks, _ = self.blk_det(x, detect=True)
        return blks[0]


def iou(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1]); x1, y1 = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, x1 - x0) * max(0, y1 - y0)
    return inter / ((a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - inter + 1e-9)


net = TextDetBase(cache.comic_text_detector, device="cpu", act="leaky").eval()
m = BlocksOnly(net).eval()
results = {}
for size in (1024, 640):
    out = HERE / f"models/detector_blocks_{size}_fp32.onnx"
    torch.onnx.export(m, torch.zeros(1, 3, size, size), str(out), input_names=["image"], output_names=["blks"],
                      opset_version=17, dynamo=False, do_constant_folding=True)
    out16 = HERE / f"models/detector_blocks_{size}_fp16.onnx"
    onnx.save(convert_float_to_float16(onnx.load(str(out)), keep_io_types=True), str(out16))
    for path, prov in [(out, ["CPUExecutionProvider"]), (out16, ["CoreMLExecutionProvider", "CPUExecutionProvider"]),
                       (out, ["CoreMLExecutionProvider", "CPUExecutionProvider"])]:
        sess = ort.InferenceSession(str(path), providers=prov)
        tp = fn = fp = 0; ms = []
        for pj in pages:
            ref = json.loads(pj.read_text())
            pil = ImageOps.exif_transpose(Image.open(Path.home() / "Downloads/frieren_ch01" / f"{ref['page']}.jpg")).convert("RGB")
            bgr = np.ascontiguousarray(np.array(pil)[:, :, ::-1])
            x, ratio, dw, dh = preprocess_img(bgr, input_size=(size, size), to_tensor=True)
            t0 = time.perf_counter(); blks = sess.run(None, {"image": x.numpy()})[0]; ms.append((time.perf_counter() - t0) * 1000)
            rr = (pil.width / (size - dw), pil.height / (size - dh))
            boxes, cls, confs = postprocess_yolo(torch.from_numpy(blks)[None], 0.4, 0.35, rr)
            got = [list(map(int, b)) for b in boxes]
            refb = [b["box"] for b in ref["blocks"]]
            matched = set()
            for g in got:
                j = max(range(len(refb)), key=lambda k: iou(g, refb[k]), default=None)
                if j is not None and iou(g, refb[j]) >= 0.5 and j not in matched: matched.add(j); tp += 1
                else: fp += 1
            fn += len(refb) - len(matched)
        name = f"blocks-only {size} {path.suffix and path.stem.split('_')[-1]} {'coreml' if 'CoreML' in prov[0] else 'cpu'}"
        results[name] = {"recall": round(tp / (tp + fn), 3), "precision": round(tp / max(1, tp + fp), 3),
                         "median_ms": round(st.median(ms[1:])), "size_mb": round(path.stat().st_size / 1e6, 1),
                         "provider": sess.get_providers()[0]}
        print(name, results[name], flush=True)
(HERE / "results/live_detector.json").write_text(json.dumps(results, indent=1))
