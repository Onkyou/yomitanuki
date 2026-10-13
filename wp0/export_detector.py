"""WP0: export comic-text-detector (the model mokuro uses) to ONNX and check parity.

Input:  BGR->RGB float32 NCHW (1,3,1024,1024), letterboxed (pad bottom/right), /255.
Output: blks  (1, 64512, 7)   yolov5 raw detections [cx,cy,w,h,obj,cls0,cls1]
        mask  (1, 1, 1024, 1024)  text pixel mask (sigmoid)
        lines (1, 2, 1024, 1024)  DBNet shrink map + threshold map
Writes models/detector_fp32.onnx and prints max abs diff torch vs ORT on a real page.
"""
import sys, time
from pathlib import Path
import numpy as np, torch, onnx, onnxruntime as ort
from PIL import Image, ImageOps
from comic_text_detector.basemodel import TextDetBase
from comic_text_detector.inference import preprocess_img
from mokuro.cache import cache

HERE = Path(__file__).parent
OUT = HERE / "models/detector_fp32.onnx"


class Wrapper(torch.nn.Module):
    def __init__(self, net):
        super().__init__(); self.net = net
    def forward(self, x):
        blks, mask, lines = self.net(x)
        return blks, mask, lines


def main():
    net = TextDetBase(cache.comic_text_detector, device="cpu", act="leaky").eval()
    w = Wrapper(net).eval()
    x = torch.zeros(1, 3, 1024, 1024)
    with torch.no_grad():
        outs = w(x)
    print("torch output shapes", [tuple(o.shape) for o in outs])
    torch.onnx.export(w, x, str(OUT), input_names=["image"], output_names=["blks", "mask", "lines"],
                      opset_version=17, dynamo=False, do_constant_folding=True)
    m = onnx.load(str(OUT)); onnx.checker.check_model(m)
    print(f"wrote {OUT} {OUT.stat().st_size/1e6:.1f} MB, opset {m.opset_import[0].version}")

    # parity on a real page
    pages = sorted((Path.home() / "Downloads/frieren_ch01").glob("IMG_*.jpg"))
    pil = ImageOps.exif_transpose(Image.open(pages[2])).convert("RGB")
    bgr = np.ascontiguousarray(np.array(pil)[:, :, ::-1])
    t_in, ratio, dw, dh = preprocess_img(bgr, input_size=(1024, 1024), device="cpu", to_tensor=True)
    with torch.no_grad():
        ref = [o.numpy() for o in w(t_in)]
    sess = ort.InferenceSession(str(OUT), providers=["CPUExecutionProvider"])
    got = sess.run(None, {"image": t_in.numpy()})
    for name, a, b in zip(["blks", "mask", "lines"], ref, got):
        print(f"{name}: shape {a.shape} max|diff| {np.abs(a-b).max():.2e}")
    for _ in range(2): sess.run(None, {"image": t_in.numpy()})
    t0 = time.perf_counter(); n = 5
    for _ in range(n): sess.run(None, {"image": t_in.numpy()})
    print(f"ORT CPU fp32 latency: {(time.perf_counter()-t0)/n*1000:.0f} ms / page")
    t0 = time.perf_counter()
    with torch.no_grad():
        for _ in range(n): w(t_in)
    print(f"torch CPU fp32 latency: {(time.perf_counter()-t0)/n*1000:.0f} ms / page")


if __name__ == "__main__":
    main()
