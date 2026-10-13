"""Run the built app graphs (app/assets/models/) the way the Dart port will: BGRA uint8 in,
boxes / token ids out. Shared by validate_graphs.py, make_goldens.py and check_goldens.py.

This is deliberately thin: everything that used to be pixel work in ocr_ort.py is now inside the
graphs (D0.9). What stays outside and therefore must exist in Dart: the greedy decode loop and
the detokenisation (both unchanged from WP0, D0.2 / ocr_ort.py)."""
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image

from ocr_ort import post_process

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "app/assets/models"
CLS, SEP = 2, 3
MAX_LEN = 300
CONF_DEFAULT = 0.2  # D0.11


def to_bgra(img: Image.Image) -> np.ndarray:
    """PIL image -> uint8 [1,H,W,4] BGRA, tightly packed (the BgraImage layout)."""
    rgba = np.asarray(img.convert("RGBA"))
    bgra = rgba[:, :, [2, 1, 0, 3]]
    return np.ascontiguousarray(bgra)[None]


class AppGraphs:
    def __init__(self, models: Path = MODELS, providers=("CPUExecutionProvider",), threads: int | None = None):
        so = ort.SessionOptions()
        if threads:
            so.intra_op_num_threads = threads
        self.det = ort.InferenceSession(str(models / "detector.onnx"), so, providers=list(providers))
        self.enc = ort.InferenceSession(str(models / "ocr_encoder.onnx"), so, providers=list(providers))
        self.dec = ort.InferenceSession(str(models / "ocr_decoder.onnx"), so, providers=list(providers))
        self.vocab = (models / "vocab.txt").read_text(encoding="utf-8").split("\n")

    def detect(self, bgra: np.ndarray, conf: float = CONF_DEFAULT) -> np.ndarray:
        """-> float32 [N,5] x0,y0,x1,y1,score in input pixels, score descending."""
        return self.det.run(None, {"image": bgra, "conf_threshold": np.array([conf], np.float32)})[0]

    def encode(self, bgra: np.ndarray) -> np.ndarray:
        return self.enc.run(None, {"image": bgra})[0]

    def greedy_ids(self, hidden: np.ndarray) -> list[int]:
        """The decode loop Dart reproduces: no KV cache, whole prefix each step, stop at [SEP]."""
        ids = [CLS]
        for _ in range(MAX_LEN - 1):
            logits = self.dec.run(None, {"input_ids": np.array([ids], np.int64), "encoder_hidden_states": hidden})[0]
            nxt = int(logits[0, -1].argmax())
            ids.append(nxt)
            if nxt == SEP:
                break
        return ids

    def ocr_ids(self, bgra: np.ndarray) -> list[int]:
        return self.greedy_ids(self.encode(bgra))

    def detokenise(self, ids) -> str:
        toks = [self.vocab[i] for i in ids if i > 4 and not self.vocab[i].startswith("<unused")]
        return post_process("".join(toks))

    def ocr(self, bgra: np.ndarray) -> str:
        return self.detokenise(self.ocr_ids(bgra))
