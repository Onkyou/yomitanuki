"""WP0: manga-ocr inference with ONNX Runtime and NO transformers at runtime.

Everything here is what the Dart port has to reproduce:
  preprocess : grayscale -> RGB, resize 224x224 bilinear, /255, (x-0.5)/0.5, NCHW
  encode     : pixel_values -> last_hidden_state (1,197,768)
  decode     : greedy loop, no KV cache: feed the whole prefix each step, take argmax of
               the last position; start [CLS]=2, stop at [SEP]=3, max 300 tokens
  detokenise : char vocab (no '##' pieces), skip ids < 5 and <unusedN>, then manga_ocr.post_process
"""
import re, time
from pathlib import Path
import numpy as np
import onnxruntime as ort
from PIL import Image
import jaconv

CLS, SEP, PAD = 2, 3, 0
MAX_LEN = 300


def post_process(text):  # copied from manga_ocr.ocr.post_process
    text = "".join(text.split())
    text = text.replace("…", "...")
    text = re.sub("[・.]{2,}", lambda x: (x.end() - x.start()) * ".", text)
    return jaconv.h2z(text, ascii=True, digit=True)


def preprocess(img: Image.Image) -> np.ndarray:
    img = img.convert("L").convert("RGB").resize((224, 224), Image.BILINEAR)
    x = np.asarray(img, dtype=np.float32) / 255.0
    x = (x - 0.5) / 0.5
    return np.ascontiguousarray(x.transpose(2, 0, 1)[None])  # (1,3,224,224)


class OrtMangaOcr:
    def __init__(self, model_dir: Path, providers=("CPUExecutionProvider",), threads=None):
        so = ort.SessionOptions()
        if threads:
            so.intra_op_num_threads = threads
        self.enc = ort.InferenceSession(str(model_dir / "encoder_model.onnx"), so, providers=list(providers))
        self.dec = ort.InferenceSession(str(model_dir / "decoder_model.onnx"), so, providers=list(providers))
        self.vocab = (model_dir / "vocab.txt").read_text(encoding="utf-8").split("\n")
        self.last = {}

    def generate_ids(self, pixel_values: np.ndarray, no_repeat_ngram: int = 0) -> list[int]:
        t0 = time.perf_counter()
        hidden = self.enc.run(None, {"pixel_values": pixel_values})[0]
        t1 = time.perf_counter()
        ids = [CLS]
        for _ in range(MAX_LEN - 1):
            logits = self.dec.run(None, {"input_ids": np.array([ids], dtype=np.int64),
                                         "encoder_hidden_states": hidden})[0]
            last = logits[0, -1]
            if no_repeat_ngram and len(ids) >= no_repeat_ngram:
                # transformers' no_repeat_ngram_size: ban any token that would complete an n-gram already seen
                n = no_repeat_ngram
                prefix = tuple(ids[-(n - 1):]) if n > 1 else ()
                for j in range(len(ids) - n + 1):
                    if tuple(ids[j:j + n - 1]) == prefix:
                        last[ids[j + n - 1]] = -np.inf
            nxt = int(last.argmax())
            ids.append(nxt)
            if nxt == SEP:
                break
        self.last = {"enc_s": t1 - t0, "dec_s": time.perf_counter() - t1, "steps": len(ids) - 1}
        return ids

    def detokenise(self, ids) -> str:
        toks = []
        for i in ids:
            if i in (PAD, 1, CLS, SEP, 4):
                continue
            t = self.vocab[i]
            if t.startswith("<unused"):
                continue
            toks.append(t)
        return post_process("".join(toks))

    def __call__(self, img: Image.Image, no_repeat_ngram: int = 0) -> str:
        return self.detokenise(self.generate_ids(preprocess(img), no_repeat_ngram))
