"""Writes the three tiny ONNX graphs the ort_ffi tests load (test/fixtures/*.onnx).

Deterministic, no weights from any model. Run with the WP0 venv (wp0/README.md):
    wp0/.venv/bin/python -I app/packages/ort_ffi/tool/make_fixtures.py
"""

import pathlib

from onnx import TensorProto, checker, helper

OUT = pathlib.Path(__file__).resolve().parent.parent / "test" / "fixtures"
OPSET, IR = 17, 8


def save(name, nodes, inputs, outputs, initializers=()):
    graph = helper.make_graph(nodes, name, inputs, outputs, list(initializers))
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", OPSET)], ir_version=IR)
    checker.check_model(model)
    (OUT / f"{name}.onnx").write_bytes(model.SerializeToString())


def tensor(name, dtype, dims):
    return helper.make_tensor_value_info(name, dtype, dims)


OUT.mkdir(parents=True, exist_ok=True)
# affine: y = x * 2 + 1 on float32 [1, n]
save("affine",
     [helper.make_node("Mul", ["x", "two"], ["t"]), helper.make_node("Add", ["t", "one"], ["y"])],
     [tensor("x", TensorProto.FLOAT, [1, "n"])], [tensor("y", TensorProto.FLOAT, [1, "n"])],
     [helper.make_tensor("two", TensorProto.FLOAT, [], [2.0]), helper.make_tensor("one", TensorProto.FLOAT, [], [1.0])])
# cast: pixels uint8 [1, 2, 2, 3] -> float32 / 255 (the shape of a BGRA-style image input)
save("cast",
     [helper.make_node("Cast", ["pixels"], ["f"], to=TensorProto.FLOAT), helper.make_node("Div", ["f", "scale"], ["norm"])],
     [tensor("pixels", TensorProto.UINT8, [1, 2, 2, 3])], [tensor("norm", TensorProto.FLOAT, [1, 2, 2, 3])],
     [helper.make_tensor("scale", TensorProto.FLOAT, [], [255.0])])
# ids: int64 ids [1, n] + int64 offset [1] -> int64 [1, n] (decoder-style token ids)
save("ids",
     [helper.make_node("Add", ["ids", "offset"], ["shifted"])],
     [tensor("ids", TensorProto.INT64, [1, "n"]), tensor("offset", TensorProto.INT64, [1])],
     [tensor("shifted", TensorProto.INT64, [1, "n"])])
