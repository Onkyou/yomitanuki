"""WP0: produce quantised variants of the exported ONNX graphs.

int8: ORT dynamic quantisation (MatMul/Gemm weights int8, activations quantised at runtime).
fp16: all float tensors to float16 (what the CoreML/NPU path effectively runs anyway).
"""
import sys, shutil
from pathlib import Path
import onnx
from onnxruntime.quantization import quantize_dynamic, QuantType
from onnxruntime.transformers.float16 import convert_float_to_float16

M = Path(__file__).parent / "models"
jobs = [("ocr_fp32/encoder_model.onnx", "ocr_int8/encoder_model.onnx"),
        ("ocr_fp32/decoder_model.onnx", "ocr_int8/decoder_model.onnx"),
        ("detector_fp32.onnx", "detector_int8.onnx")]
for src, dst in jobs:
    (M / dst).parent.mkdir(exist_ok=True)
    quantize_dynamic(str(M / src), str(M / dst), weight_type=QuantType.QInt8)
    print(f"int8 {dst}: {(M/dst).stat().st_size/1e6:.1f} MB", flush=True)
for src, dst in [("ocr_fp32/encoder_model.onnx", "ocr_fp16/encoder_model.onnx"),
                 ("ocr_fp32/decoder_model.onnx", "ocr_fp16/decoder_model.onnx"),
                 ("detector_fp32.onnx", "detector_fp16.onnx")]:
    (M / dst).parent.mkdir(exist_ok=True)
    m = onnx.load(str(M / src))
    m16 = convert_float_to_float16(m, keep_io_types=True)
    onnx.save(m16, str(M / dst))
    print(f"fp16 {dst}: {(M/dst).stat().st_size/1e6:.1f} MB", flush=True)
for d in ["ocr_int8", "ocr_fp16"]:
    shutil.copy(M / "ocr_fp32/vocab.txt", M / d / "vocab.txt")
