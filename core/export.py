"""Export quantized weights to ROM init files and golden test vectors."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    DATA_WIDTH,
    FRAC_BITS,
    HIDDEN_SIZE,
    INPUT_SIZE,
    METADATA_JSON,
    OUTPUT_SIZE,
    QUANT_WEIGHTS_NPZ,
    TEST_VECTORS_DIR,
    VHDL_RTL_DIR,
    WEIGHTS_DIR,
)
from mnist_loader import load_mnist
from quantization import fixed_point_forward, float_to_q88, load_quant_params


def _to_hex16(v: int) -> str:
    return f"{np.uint16(np.int16(v)):04x}"


def write_mem(path: Path, values: np.ndarray) -> None:
    flat = values.astype(np.int16).reshape(-1)
    lines = [_to_hex16(int(v)) for v in flat]
    path.write_text("\n".join(lines) + "\n")


def write_rom_package(
    path: Path,
    w1: np.ndarray,
    b1: np.ndarray,
    w2: np.ndarray,
    b2: np.ndarray,
) -> None:
    """Emit a VHDL package with weight/bias arrays as constants."""

    def arr_1d(name: str, data: np.ndarray, length: int) -> str:
        elems = ", ".join(f'x"{_to_hex16(int(v))}"' for v in data.reshape(-1))
        return (
            f"  type {name}_t is array (0 to {length - 1}) of std_logic_vector(15 downto 0);\n"
            f"  constant {name} : {name}_t := (\n    {elems}\n  );\n"
        )

    # Flatten W as row-major: neuron0 all inputs, neuron1 ...
    w1_flat = w1.reshape(-1)
    w2_flat = w2.reshape(-1)
    body = []
    body.append("library ieee;")
    body.append("use ieee.std_logic_1164.all;")
    body.append("use ieee.numeric_std.all;")
    body.append("")
    body.append("package pkg_weights is")
    body.append(f"  constant INPUT_SIZE  : integer := {INPUT_SIZE};")
    body.append(f"  constant HIDDEN_SIZE : integer := {HIDDEN_SIZE};")
    body.append(f"  constant OUTPUT_SIZE : integer := {OUTPUT_SIZE};")
    body.append("")
    body.append(arr_1d("W1", w1_flat, w1_flat.size))
    body.append(arr_1d("B1", b1, b1.size))
    body.append(arr_1d("W2", w2_flat, w2_flat.size))
    body.append(arr_1d("B2", b2, b2.size))
    body.append("end package pkg_weights;")
    path.write_text("\n".join(body) + "\n")


def export_test_vectors(qparams: dict[str, np.ndarray], n_samples: int = 10) -> None:
    TEST_VECTORS_DIR.mkdir(parents=True, exist_ok=True)
    x_test, y_test = load_mnist("test")
    # Prefer diverse digits
    chosen: list[int] = []
    for digit in range(10):
        idxs = np.where(y_test == digit)[0]
        if len(idxs):
            chosen.append(int(idxs[0]))
    chosen = chosen[:n_samples]

    x = x_test[chosen]
    y = y_test[chosen]
    logits_q, hidden_q = fixed_point_forward(qparams, x)
    pred = np.argmax(logits_q, axis=1)

    # One combined file for TB: each sample starts with label, pred, then 784 hex pixels
    manifest = []
    for i, idx in enumerate(chosen):
        sample_dir = TEST_VECTORS_DIR / f"sample_{i:02d}"
        sample_dir.mkdir(parents=True, exist_ok=True)
        x_q = float_to_q88(x[i])
        write_mem(sample_dir / "input.mem", x_q)
        (sample_dir / "label.txt").write_text(f"{int(y[i])}\n")
        (sample_dir / "expected_class.txt").write_text(f"{int(pred[i])}\n")
        write_mem(sample_dir / "hidden.mem", hidden_q[i])
        write_mem(sample_dir / "logits.mem", logits_q[i])
        manifest.append(
            {
                "index": i,
                "mnist_index": int(idx),
                "label": int(y[i]),
                "expected_class": int(pred[i]),
            }
        )

    # Flat files for simple VHDL TB (sample 0 default + list)
    write_mem(TEST_VECTORS_DIR / "input_0.mem", float_to_q88(x[0]))
    (TEST_VECTORS_DIR / "expected_0.txt").write_text(f"{int(pred[0])}\n")

    # Multi-sample class list
    (TEST_VECTORS_DIR / "expected_classes.txt").write_text(
        "\n".join(str(int(p)) for p in pred) + "\n"
    )
    # Concatenated inputs: N * 784 lines
    all_in = np.concatenate([float_to_q88(x[i]) for i in range(len(chosen))])
    write_mem(TEST_VECTORS_DIR / "inputs_all.mem", all_in)
    (TEST_VECTORS_DIR / "num_samples.txt").write_text(f"{len(chosen)}\n")

    (TEST_VECTORS_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"Exported {len(chosen)} test vectors → {TEST_VECTORS_DIR}")


def main() -> None:
    if not QUANT_WEIGHTS_NPZ.exists():
        raise SystemExit(f"Missing {QUANT_WEIGHTS_NPZ}; run python/quantization.py first")

    qparams = load_quant_params()
    w1, b1, w2, b2 = qparams["w1"], qparams["b1"], qparams["w2"], qparams["b2"]

    WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
    VHDL_RTL_DIR.mkdir(parents=True, exist_ok=True)

    write_mem(WEIGHTS_DIR / "w1.mem", w1)
    write_mem(WEIGHTS_DIR / "b1.mem", b1)
    write_mem(WEIGHTS_DIR / "w2.mem", w2)
    write_mem(WEIGHTS_DIR / "b2.mem", b2)
    write_rom_package(VHDL_RTL_DIR / "pkg_weights.vhd", w1, b1, w2, b2)

    meta = {
        "input_size": INPUT_SIZE,
        "hidden_size": int(w1.shape[0]),
        "output_size": OUTPUT_SIZE,
        "data_width": DATA_WIDTH,
        "frac_bits": FRAC_BITS,
        "format": "Q8.8",
        "weight_layout": "row-major per neuron",
        "files": {
            "w1": "weights/w1.mem",
            "b1": "weights/b1.mem",
            "w2": "weights/w2.mem",
            "b2": "weights/b2.mem",
            "pkg_weights": "vhdl/rtl/pkg_weights.vhd",
        },
    }
    METADATA_JSON.write_text(json.dumps(meta, indent=2))
    print(f"Wrote ROM files and {METADATA_JSON}")

    export_test_vectors(qparams, n_samples=10)


if __name__ == "__main__":
    main()
