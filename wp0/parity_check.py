"""Decode-loop parity: ORT greedy (hand-rolled) must equal torch generate(num_beams=1) token for token,
and the preprocessing must match ViTImageProcessor."""
import json, sys
from pathlib import Path
import numpy as np, torch
from PIL import Image
from transformers import ViTImageProcessor, AutoTokenizer, VisionEncoderDecoderModel
from ocr_ort import OrtMangaOcr, preprocess

HERE = Path(__file__).parent
man = json.loads((HERE / "fixtures/private/manifest.json").read_text())
n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
proc = ViTImageProcessor.from_pretrained("kha-white/manga-ocr-base")
tok = AutoTokenizer.from_pretrained("kha-white/manga-ocr-base")
model = VisionEncoderDecoderModel.from_pretrained("kha-white/manga-ocr-base").eval()
ocr = OrtMangaOcr(HERE / "models/ocr_fp32")
bad = 0
for e in man[:n]:
    img = Image.open(HERE / "fixtures/private/crops" / e["crop"]).convert("L").convert("RGB")
    ref_px = proc(img, return_tensors="pt").pixel_values
    px = preprocess(img)
    pre_diff = float(np.abs(ref_px.numpy() - px).max())
    with torch.no_grad():
        ref_ids = model.generate(ref_px, max_length=300, num_beams=1, do_sample=False,
                                 no_repeat_ngram_size=0, early_stopping=False, length_penalty=1.0)[0].tolist()
    ids = ocr.generate_ids(px)
    same = ids == ref_ids
    bad += not same
    ref_txt = tok.decode(ref_ids, skip_special_tokens=True)
    print(f"{e['crop']} pre|diff|={pre_diff:.1e} ids_equal={same} ort='{ocr.detokenise(ids)}' torch_greedy='{ref_txt}' beam4='{e['text_fp32']}'")
print("mismatching sequences:", bad, "of", n)
