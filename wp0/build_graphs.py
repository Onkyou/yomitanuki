"""WP0b: build the three ONNX graphs the app ships, with the preprocessing baked in (D0.9).

The graphs ARE the contract (see .claude/wp0/NOTES.md, "What the Dart port has to reproduce"):
Dart hands each graph a raw BGRA uint8 image and reads boxes or hidden states back; no pixel loop,
no NMS in Dart (C12). Outputs go to app/assets/models/ (gitignored, D6), rebuilt by `make models`.

  detector.onnx     image uint8 [1,H,W,4] BGRA + conf_threshold float32 [1]
                    -> blocks float32 [N,5] = x0,y0,x1,y1,score in input pixels, score descending
                    (drop alpha, keep B,G,R (C1), letterbox as comic-text-detector (C10), /255,
                     blocks-only yolov5 head (D0.7), decode, best class, class-aware NMS IoU 0.35)
  ocr_encoder.onnx  image uint8 [1,H,W,4] BGRA crop -> encoder_hidden_states float32 [1,197,768]
                    (PIL-exact grey, antialiased bilinear resize to 224 (C2), /255, (x-0.5)/0.5,
                     ViT encoder; int8 dynamic weights, preprocessing stays float)
  ocr_decoder.onnx  input_ids int64 [1,L] + encoder_hidden_states -> logits float32 [1,L,6144]
                    (the optimum decoder, int8 dynamic, I/O unchanged)
  vocab.txt, manifest.json (sha256, sizes, opsets, the I/O contract)

Usage: wp0/.venv/bin/python wp0/build_graphs.py [--force-export]
Intermediates (the fp32 exports) live in wp0/models/ (gitignored). The fp32 exports are
deterministic (C8); the quantisation is checked for determinism by `--check-determinism`.
"""
import argparse
import hashlib
import json
import shutil
from importlib.metadata import version as pkg_version
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto as TP
from onnx import helper, version_converter
from onnxruntime.quantization import QuantType, quantize_dynamic

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MODELS = HERE / "models"
OUT = ROOT / "app/assets/models"
OCR_REPO = "kha-white/manga-ocr-base"
# The commit of OCR_REPO the export is pinned to (main as of 2026-10-20, last modified 2022-06-22):
# a floating "main" would let a re-published weight change the graphs under the goldens.
OCR_REVISION = "aa6573bd10b0d446cbf622e29c3e084914df9741"
DET_SIZE = 1024
OCR_SIZE = 224
NMS_IOU = 0.35
NMS_MAX_PER_CLASS = 300
CONF_DEFAULT = 0.2  # D0.11
# PIL's ImagingConvert L: (R*19595 + G*38470 + B*7471 + 0x8000) >> 16, integer arithmetic.
GREY_WEIGHTS_BGR = [7471, 38470, 19595]


# --- small onnx.helper conveniences ------------------------------------------------------------

def const(name, dtype, values):
    arr = np.asarray(values)
    return helper.make_tensor(name, dtype, arr.shape, arr.flatten().tolist())


def node(op, inputs, outputs, **attrs):
    return helper.make_node(op, inputs, outputs, name=f"{op}_{outputs[0]}", **attrs)


def rename_tensor(model: onnx.ModelProto, old: str, new: str):
    """Rename a tensor everywhere it appears (graph inputs/outputs, value_info, node inputs/outputs)."""
    for vi in list(model.graph.input) + list(model.graph.value_info) + list(model.graph.output):
        if vi.name == old:
            vi.name = new
    for n in model.graph.node:
        for i, name in enumerate(n.input):
            if name == old:
                n.input[i] = new
        for i, name in enumerate(n.output):
            if name == old:
                n.output[i] = new


def splice(net: onnx.ModelProto, pre_nodes, pre_inits, post_nodes, post_inits, inputs, outputs,
           extra_value_info, opset):
    """New model = pre_nodes + net.graph.node + post_nodes, with net's initializers and value_info."""
    g = helper.make_graph(
        list(pre_nodes) + list(net.graph.node) + list(post_nodes),
        net.graph.name,
        inputs, outputs,
        initializer=list(pre_inits) + list(net.graph.initializer) + list(post_inits),
        value_info=list(net.graph.value_info) + list(extra_value_info),
    )
    m = helper.make_model(g, opset_imports=[helper.make_opsetid("", opset)], producer_name="yomitanuki-wp0b")
    m.ir_version = net.ir_version
    onnx.checker.check_model(m)
    return m


# --- fp32 exports (deterministic, C8) ------------------------------------------------------------

def export_ocr_fp32(force: bool) -> Path:
    out = MODELS / "ocr_fp32"
    needed = [out / "encoder_model.onnx", out / "decoder_model.onnx", out / "vocab.txt"]
    if not force and all(p.exists() for p in needed):
        print(f"ocr fp32 export present: {out}")
        return out
    # optimum.exporters.onnx.main_export is what `optimum-cli export onnx` calls; the CLI of
    # optimum-onnx 0.1.0 has no --revision flag, so the pin is passed to the function directly.
    from optimum.exporters.onnx import main_export
    print(f"$ optimum export onnx {OCR_REPO}@{OCR_REVISION} --task image-to-text --opset 17 {out}", flush=True)
    main_export(OCR_REPO, output=out, task="image-to-text", opset=17, revision=OCR_REVISION)
    return out


def export_detector_blocks_fp32(force: bool) -> Path:
    """The blocks-only yolov5 head (D0.7), exactly as wp0/live_detector.py exported it."""
    out = MODELS / f"detector_blocks_{DET_SIZE}_fp32.onnx"
    if not force and out.exists():
        print(f"detector fp32 export present: {out}")
        return out
    import torch
    from comic_text_detector.basemodel import TextDetBase
    from mokuro.cache import cache

    class BlocksOnly(torch.nn.Module):
        def __init__(self, net):
            super().__init__()
            self.blk_det = net.blk_det

        def forward(self, x):
            blks, _ = self.blk_det(x, detect=True)
            return blks[0]

    net = TextDetBase(cache.comic_text_detector, device="cpu", act="leaky").eval()
    m = BlocksOnly(net).eval()
    torch.onnx.export(m, torch.zeros(1, 3, DET_SIZE, DET_SIZE), str(out), input_names=["image"],
                      output_names=["blks"], opset_version=17, dynamo=False, do_constant_folding=True)
    onnx.checker.check_model(onnx.load(str(out)))
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB)")
    return out


# --- detector: BGRA in, boxes out ------------------------------------------------------------------

def build_detector(net_path: Path) -> onnx.ModelProto:
    net = onnx.load(str(net_path))
    rename_tensor(net, "image", "det_pre_tensor")
    S = float(DET_SIZE)
    pre = [
        # drop alpha; B,G,R stays (C1: the network consumes BGR)
        node("Slice", ["image", "c_0", "c_3", "c_ax3"], ["det_bgr"]),
        node("Transpose", ["det_bgr"], ["det_bgr_nchw"], perm=[0, 3, 1, 2]),
        node("Cast", ["det_bgr_nchw"], ["det_f"], to=TP.FLOAT),
        # letterbox (C10): r = min(S/H, S/W); new = round(shape * r) (round half to even, like Python)
        node("Shape", ["image"], ["det_shape"]),
        node("Gather", ["det_shape", "c_idx_hw"], ["det_hw"], axis=0),
        node("Cast", ["det_hw"], ["det_hw_f"], to=TP.FLOAT),
        node("Div", ["c_size_f", "det_hw_f"], ["det_ratios"]),
        node("ReduceMin", ["det_ratios"], ["det_r"], keepdims=1),
        node("Mul", ["det_hw_f", "det_r"], ["det_new_hw_raw"]),
        node("Round", ["det_new_hw_raw"], ["det_new_hw_rounded"]),
        # a side thinner than 1/2048 of the other would round to 0 px; keep it at 1 so Resize is valid
        node("Max", ["det_new_hw_rounded", "c_one_f"], ["det_new_hw_f"]),
        node("Cast", ["det_new_hw_f"], ["det_new_hw"], to=TP.INT64),
        node("Concat", ["c_13", "det_new_hw"], ["det_sizes"], axis=0),
        # cv2.INTER_LINEAR: plain bilinear, half-pixel centres, no antialias
        node("Resize", ["det_f", "", "", "det_sizes"], ["det_resized"], mode="linear",
             coordinate_transformation_mode="half_pixel"),
        node("Sub", ["c_size_i2", "det_new_hw"], ["det_pad_hw"]),
        node("Concat", ["c_pad_lead", "det_pad_hw"], ["det_pads"], axis=0),
        node("Pad", ["det_resized", "det_pads", "c_zero_f"], ["det_padded"], mode="constant"),
        node("Div", ["det_padded", "c_255"], ["det_pre_tensor"]),
    ]
    pre_inits = [
        const("c_0", TP.INT64, [0]), const("c_3", TP.INT64, [3]), const("c_ax3", TP.INT64, [3]),
        const("c_idx_hw", TP.INT64, [1, 2]), const("c_size_f", TP.FLOAT, [S, S]),
        const("c_13", TP.INT64, [1, 3]), const("c_size_i2", TP.INT64, [DET_SIZE, DET_SIZE]),
        const("c_pad_lead", TP.INT64, [0, 0, 0, 0, 0, 0]), const("c_zero_f", TP.FLOAT, [0.0]),
        const("c_one_f", TP.FLOAT, [1.0]), const("c_255", TP.FLOAT, [255.0]),
    ]
    post = [
        # blks [1,N,7] = cx,cy,w,h,obj,cls0,cls1 (sigmoid applied); xywh -> xyxy in letterbox pixels
        node("Slice", ["blks", "c_0", "c_2", "c_ax2"], ["det_xy"]),
        node("Slice", ["blks", "c_2", "c_4", "c_ax2"], ["det_wh"]),
        node("Slice", ["blks", "c_4", "c_5", "c_ax2"], ["det_obj"]),
        node("Slice", ["blks", "c_5", "c_7", "c_ax2"], ["det_cls"]),
        node("Mul", ["det_wh", "c_half"], ["det_half_wh"]),
        node("Sub", ["det_xy", "det_half_wh"], ["det_xy0"]),
        node("Add", ["det_xy", "det_half_wh"], ["det_xy1"]),
        node("Concat", ["det_xy0", "det_xy1"], ["det_boxes"], axis=2),  # [1,N,4]
        # best class only: conf = obj * max(cls); score of the other class is 0 (never selected)
        node("ReduceMax", ["det_cls"], ["det_cls_max"], axes=[2], keepdims=1),  # opset 17: axes is an attribute
        node("Mul", ["det_obj", "det_cls_max"], ["det_conf"]),  # [1,N,1]
        node("ArgMax", ["det_cls"], ["det_best"], axis=2, keepdims=1),  # [1,N,1] int64
        node("Equal", ["det_best", "c_classes"], ["det_onehot"]),  # [1,N,2]
        node("Where", ["det_onehot", "det_conf", "c_zero_f"], ["det_scores_nc"]),  # [1,N,2]
        node("Transpose", ["det_scores_nc"], ["det_scores"], perm=[0, 2, 1]),  # [1,2,N]
        # class-aware NMS, candidates conf > conf_threshold (obj > t is implied: conf <= obj).
        # The threshold is clipped to [0,1]: a negative one would admit the zero-scored other-class entries.
        node("Clip", ["conf_threshold", "c_zero_s", "c_one_s"], ["det_conf_t"]),
        node("NonMaxSuppression", ["det_boxes", "det_scores", "c_nms_max", "c_nms_iou", "det_conf_t"],
             ["det_sel"], center_point_box=0),  # [M,3] = batch, class, box
        node("Gather", ["det_sel", "c_2s"], ["det_idx"], axis=1),  # [M] box indices (scalar index drops the axis)
        node("Squeeze", ["det_boxes", "c_ax0"], ["det_boxes_n"]),  # [N,4]
        node("Squeeze", ["det_conf", "c_ax02"], ["det_conf_n"]),  # [N]
        node("Gather", ["det_boxes_n", "det_idx"], ["det_boxes_sel"], axis=0),  # [M,4]
        node("Gather", ["det_conf_n", "det_idx"], ["det_conf_sel"], axis=0),  # [M]
        # letterbox -> input pixels: x * W/new_w, y * H/new_h (C10)
        node("Div", ["det_hw_f", "det_new_hw_f"], ["det_back_hw"]),  # [2] = (H/nh, W/nw)
        node("Gather", ["det_back_hw", "c_xyxy_from_hw"], ["det_back_xyxy"], axis=0),  # [4]
        node("Mul", ["det_boxes_sel", "det_back_xyxy"], ["det_boxes_px"]),
        # order by score descending across classes (torchvision nms order)
        node("Shape", ["det_conf_sel"], ["det_m"]),
        node("TopK", ["det_conf_sel", "det_m"], ["det_score_sorted", "det_order"], axis=0, largest=1, sorted=1),
        node("Gather", ["det_boxes_px", "det_order"], ["det_boxes_sorted"], axis=0),
        node("Unsqueeze", ["det_score_sorted", "c_ax1"], ["det_score_col"]),
        node("Concat", ["det_boxes_sorted", "det_score_col"], ["blocks"], axis=1),
    ]
    post_inits = [
        const("c_2", TP.INT64, [2]), const("c_4", TP.INT64, [4]), const("c_5", TP.INT64, [5]),
        const("c_7", TP.INT64, [7]), const("c_ax2", TP.INT64, [2]), const("c_ax0", TP.INT64, [0]),
        const("c_ax1", TP.INT64, [1]), const("c_ax02", TP.INT64, [0, 2]), const("c_half", TP.FLOAT, [0.5]),
        const("c_classes", TP.INT64, np.array([[[0, 1]]], dtype=np.int64)),
        const("c_nms_max", TP.INT64, [NMS_MAX_PER_CLASS]), const("c_nms_iou", TP.FLOAT, [NMS_IOU]),
        const("c_2s", TP.INT64, np.array(2, dtype=np.int64)),
        const("c_xyxy_from_hw", TP.INT64, [1, 0, 1, 0]),
        const("c_zero_s", TP.FLOAT, np.array(0.0, dtype=np.float32)),  # Clip wants 0-d min/max
        const("c_one_s", TP.FLOAT, np.array(1.0, dtype=np.float32)),
    ]
    inputs = [helper.make_tensor_value_info("image", TP.UINT8, [1, "H", "W", 4]),
              helper.make_tensor_value_info("conf_threshold", TP.FLOAT, [1])]
    outputs = [helper.make_tensor_value_info("blocks", TP.FLOAT, ["N", 5])]
    # The network's input shape must be static in value_info or the CoreML EP will not take it.
    vi = [helper.make_tensor_value_info("det_pre_tensor", TP.FLOAT, [1, 3, DET_SIZE, DET_SIZE])]
    return splice(net, pre, pre_inits, post, post_inits, inputs, outputs, vi, opset=17)


# --- OCR encoder: BGRA crop in, hidden states out -----------------------------------------------

def build_ocr_encoder(enc_path: Path) -> onnx.ModelProto:
    net = version_converter.convert_version(onnx.load(str(enc_path)), 18)  # Resize antialias needs 18
    rename_tensor(net, "pixel_values", "ocr_pixel_values")
    # the optimum export names its output last_hidden_state; the app contract says encoder_hidden_states
    rename_tensor(net, "last_hidden_state", "encoder_hidden_states")
    pre = [
        node("Slice", ["image", "c_0", "c_3", "c_ax3"], ["ocr_bgr"]),
        # PIL ImagingConvert RGB->L, fixed point: (R*19595 + G*38470 + B*7471 + 32768) >> 16
        node("Cast", ["ocr_bgr"], ["ocr_bgr_i"], to=TP.INT32),
        node("Mul", ["ocr_bgr_i", "c_grey_w"], ["ocr_weighted"]),
        node("ReduceSum", ["ocr_weighted", "c_ax3"], ["ocr_sum"], keepdims=1),
        node("Add", ["ocr_sum", "c_grey_half"], ["ocr_sum_r"]),
        node("Div", ["ocr_sum_r", "c_grey_den"], ["ocr_grey_i"]),  # non-negative: truncation == floor
        node("Transpose", ["ocr_grey_i"], ["ocr_grey_nchw"], perm=[0, 3, 1, 2]),  # [1,1,H,W]
        node("Cast", ["ocr_grey_nchw"], ["ocr_grey_u8"], to=TP.UINT8),
        # PIL BILINEAR = triangle filter, antialiased when downscaling (C2); uint8 in, uint8 out
        node("Resize", ["ocr_grey_u8", "", "", "c_ocr_sizes"], ["ocr_resized_u8"], mode="linear",
             coordinate_transformation_mode="half_pixel", antialias=1),
        node("Cast", ["ocr_resized_u8"], ["ocr_resized"], to=TP.FLOAT),
        # ViTImageProcessor: /255, (x - 0.5) / 0.5, in this order (bit-exact with wp0/ocr_ort.py)
        node("Div", ["ocr_resized", "c_255"], ["ocr_scaled"]),
        node("Sub", ["ocr_scaled", "c_half"], ["ocr_centred"]),
        node("Div", ["ocr_centred", "c_half"], ["ocr_norm"]),
        node("Expand", ["ocr_norm", "c_ocr_shape3"], ["ocr_pixel_values"]),  # grey replicated to RGB
    ]
    pre_inits = [
        const("c_0", TP.INT64, [0]), const("c_3", TP.INT64, [3]), const("c_ax3", TP.INT64, [3]),
        const("c_grey_w", TP.INT32, GREY_WEIGHTS_BGR), const("c_grey_half", TP.INT32, [32768]),
        const("c_grey_den", TP.INT32, [65536]),
        const("c_ocr_sizes", TP.INT64, [1, 1, OCR_SIZE, OCR_SIZE]),
        const("c_255", TP.FLOAT, [255.0]), const("c_half", TP.FLOAT, [0.5]),
        const("c_ocr_shape3", TP.INT64, [1, 3, OCR_SIZE, OCR_SIZE]),
    ]
    inputs = [helper.make_tensor_value_info("image", TP.UINT8, [1, "H", "W", 4])]
    outputs = [helper.make_tensor_value_info("encoder_hidden_states", TP.FLOAT, [1, 197, 768])]
    vi = [helper.make_tensor_value_info("ocr_pixel_values", TP.FLOAT, [1, 3, OCR_SIZE, OCR_SIZE])]
    return splice(net, pre, pre_inits, [], [], inputs, outputs, vi, opset=18)


# --- quantisation, manifest, smoke test -----------------------------------------------------------

def quantise(src: Path, dst: Path):
    quantize_dynamic(str(src), str(dst), weight_type=QuantType.QInt8)
    print(f"int8 {dst.name}: {dst.stat().st_size / 1e6:.1f} MB")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def contract() -> dict:
    bgra = {"dtype": "uint8", "shape": [1, "H", "W", 4],
            "layout": "row-major BGRA, tightly packed (no row padding), any H >= 1 and W >= 1 "
                      "(a side thinner than 1/2048 of the other is letterboxed to 1 px)"}
    return {
        "detector.onnx": {
            "inputs": {"image": bgra,
                       "conf_threshold": {"dtype": "float32", "shape": [1], "default": CONF_DEFAULT, "range": [0.0, 1.0],
                                          "meaning": "keep boxes with obj*cls > conf_threshold (D0.11); "
                                                     "clipped to [0,1] inside the graph"}},
            "outputs": {"blocks": {"dtype": "float32", "shape": ["N", 5], "columns": ["x0", "y0", "x1", "y1", "score"],
                                   "units": "input pixels, xyxy, not clipped to the image, score descending"}},
            "inside": {"channels": "alpha dropped, B,G,R order kept (C1)",
                       "letterbox": f"r=min({DET_SIZE}/H,{DET_SIZE}/W), new=round(shape*r), bilinear half-pixel, "
                                    f"pad right/bottom with 0 to {DET_SIZE}x{DET_SIZE}, /255 (C10)",
                       "nms": {"class_aware": True, "iou": NMS_IOU, "max_per_class": NMS_MAX_PER_CLASS,
                               "score": "obj * best class prob"}},
        },
        "ocr_encoder.onnx": {
            "inputs": {"image": bgra},
            "outputs": {"encoder_hidden_states": {"dtype": "float32", "shape": [1, 197, 768]}},
            "inside": {"grey": "PIL L: (19595R + 38470G + 7471B + 32768) >> 16",
                       "resize": f"{OCR_SIZE}x{OCR_SIZE} bilinear, antialiased (PIL BILINEAR), uint8",
                       "normalise": "/255, (x-0.5)/0.5, grey replicated to 3 channels, NCHW"},
        },
        "ocr_decoder.onnx": {
            "inputs": {"input_ids": {"dtype": "int64", "shape": [1, "L"]},
                       "encoder_hidden_states": {"dtype": "float32", "shape": [1, 197, 768]}},
            "outputs": {"logits": {"dtype": "float32", "shape": [1, "L", 6144]}},
            "decode": {"start": 2, "stop": 3, "max_len": 300, "rule": "greedy, no KV cache: feed the whole "
                       "prefix, argmax of the last position (D0.2)"},
            "detokenise": {"skip_ids": [0, 1, 2, 3, 4], "skip_prefix": "<unused",
                           "post_process": "strip whitespace; … -> ...; runs of [・.] -> same count of '.'; "
                                           "jaconv.h2z(ascii=True, digit=True)"},
        },
    }


def write_manifest(files: dict[str, Path]):
    manifest = {
        "built_by": "wp0/build_graphs.py",
        "versions": {p: pkg_version(p) for p in ("onnxruntime", "onnx", "torch", "transformers", "optimum", "pillow")},
        "files": {name: {"sha256": sha256(p), "bytes": p.stat().st_size,
                         **({"opset": onnx.load(str(p), load_external_data=False).opset_import[0].version}
                            if p.suffix == ".onnx" else {})}
                  for name, p in files.items()},
        "contract": contract(),
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    for name, info in manifest["files"].items():
        print(f"  {name:18s} {info['bytes'] / 1e6:8.1f} MB  {info['sha256'][:16]}")


def smoke_test():
    """Shapes and edge cases on synthetic input: a blank page gives 0 boxes, a tiny crop encodes."""
    so = ort.SessionOptions()
    det = ort.InferenceSession(str(OUT / "detector.onnx"), so, providers=["CPUExecutionProvider"])
    enc = ort.InferenceSession(str(OUT / "ocr_encoder.onnx"), so, providers=["CPUExecutionProvider"])
    dec = ort.InferenceSession(str(OUT / "ocr_decoder.onnx"), so, providers=["CPUExecutionProvider"])
    blank = np.full((1, 700, 500, 4), 255, np.uint8)
    blocks = det.run(None, {"image": blank, "conf_threshold": np.array([CONF_DEFAULT], np.float32)})[0]
    assert blocks.shape == (0, 5), blocks.shape
    for shape in ((1, 4096, 1, 4), (1, 1, 4096, 4), (1, 1, 1, 4)):  # degenerate letterbox: short side -> 1 px
        assert det.run(None, {"image": np.zeros(shape, np.uint8), "conf_threshold": np.array([0.2], np.float32)})[0].shape[1] == 5
    # out-of-range thresholds are clipped: -1 behaves as 0 (every box with score > 0, but never the
    # zero-scored other-class entries), 2 behaves as 1 (nothing)
    run = lambda t: det.run(None, {"image": blank, "conf_threshold": np.array([t], np.float32)})[0]  # noqa: E731
    at_zero = run(0.0)
    assert at_zero.shape[0] > 0 and float(at_zero[:, 4].min()) > 0.0, at_zero.shape
    assert np.array_equal(run(-1.0), at_zero)
    assert run(2.0).shape == (0, 5)
    hidden = enc.run(None, {"image": np.full((1, 9, 7, 4), 128, np.uint8)})[0]
    assert hidden.shape == (1, 197, 768), hidden.shape
    logits = dec.run(None, {"input_ids": np.array([[2]], np.int64), "encoder_hidden_states": hidden})[0]
    assert logits.shape == (1, 1, 6144), logits.shape
    print("smoke test ok: blank page -> 0 blocks, conf -1 == conf 0 (clipped) and conf 2 -> 0 blocks, "
          "4096x1 / 1x4096 / 1x1 pages run, 9x7 crop -> (1,197,768), decoder -> (1,1,6144)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force-export", action="store_true", help="re-run the fp32 exports even if present")
    ap.add_argument("--check-determinism", action="store_true",
                    help="build the quantised graphs twice and compare sha256")
    args = ap.parse_args()
    MODELS.mkdir(exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)

    ocr_dir = export_ocr_fp32(args.force_export)
    det_fp32 = export_detector_blocks_fp32(args.force_export)

    onnx.save(build_detector(det_fp32), str(OUT / "detector.onnx"))
    print(f"detector.onnx: {(OUT / 'detector.onnx').stat().st_size / 1e6:.1f} MB")

    enc_fp32 = MODELS / "ocr_encoder_fp32_baked.onnx"
    onnx.save(build_ocr_encoder(ocr_dir / "encoder_model.onnx"), str(enc_fp32))
    quantise(enc_fp32, OUT / "ocr_encoder.onnx")
    quantise(ocr_dir / "decoder_model.onnx", OUT / "ocr_decoder.onnx")
    shutil.copy(ocr_dir / "vocab.txt", OUT / "vocab.txt")

    if args.check_determinism:
        for name, src in (("ocr_encoder.onnx", enc_fp32), ("ocr_decoder.onnx", ocr_dir / "decoder_model.onnx")):
            again = MODELS / f"again_{name}"
            quantize_dynamic(str(src), str(again), weight_type=QuantType.QInt8)
            same = sha256(again) == sha256(OUT / name)
            print(f"determinism {name}: {'identical' if same else 'DIFFERS'}")
            again.unlink()

    smoke_test()
    write_manifest({n: OUT / n for n in ("detector.onnx", "ocr_encoder.onnx", "ocr_decoder.onnx", "vocab.txt")})
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
